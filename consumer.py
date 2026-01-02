import json
import time
import queue
import logging
import os
import uuid
import cv2
import torch
import torch.multiprocessing as mp
import numpy as np
from torchvision import models, transforms
from confluent_kafka import Consumer
from prometheus_client import start_http_server, Gauge, Counter
from dotenv import load_dotenv
from pymongo import MongoClient
from concurrent.futures import ThreadPoolExecutor

load_dotenv()

# Config
TOPIC = os.getenv("KAFKA_TOPIC", "image_data")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", 8))
QUEUE_SIZE = int(os.getenv("QUEUE_SIZE", 200))
KAFKA_BROKER = os.getenv("KAFKA_BOOTSTRAP_SERVER", "localhost:9092")
KAFKA_CONSUMER_GROUP = os.getenv("KAFKA_CONSUMER_GROUP", "gpu_cluster_h100")
METRICS_PORT = int(os.getenv("METRICS_PORT", 8000))
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017/")
DB_NAME = os.getenv("DB_NAME", "lab_discovery_db")
STORAGE_PATH = os.getenv("STORAGE_PATH", "./discoveries")
MODEL_PATH = os.getenv("MODEL_PATH", "model.pth")
CLASSES_PATH = os.getenv("CLASSES_PATH", "classes.json")

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO
)


class DiscoverySaver:
    def __init__(self):
        os.makedirs(STORAGE_PATH, exist_ok=True)

        try:
            self.client = MongoClient(MONGO_URI)
            self.db = self.client[DB_NAME]
            self.collection = self.db["shapes_found"]
            logging.info("Connected to MongoDB.")

        except:
            self.client = None

        self.executor = ThreadPoolExecutor(max_workers=4)

    def save_hit_async(self, image_array, confidence, predicted_label, metadata):
        self.executor.submit(
            self._save_task, image_array, confidence, predicted_label, metadata
        )

    def _save_task(self, image_array, confidence, predicted_label, metadata):
        try:
            unique_id = str(uuid.uuid4())
            filename = f"hit_{unique_id}.jpg"
            filepath = os.path.join(STORAGE_PATH, filename)

            # Save BGR Image
            cv2.imwrite(filepath, image_array)

            ground_truth_str = f"{metadata.get('color_label', 'unknown')}_{metadata.get('shape_label', 'unknown')}"

            if self.client:
                doc = {
                    "_id": unique_id,
                    "timestamp": time.time(),
                    "confidence": float(confidence),
                    "predicted_label": predicted_label,
                    "ground_truth": ground_truth_str,
                    "file_path": filepath,
                }
                self.collection.insert_one(doc)
                logging.info(f"Saved to database: {predicted_label}")

        except Exception as e:
            logging.error(f"Save Error: {e}")


def fetch_data_process(data_queue: mp.Queue, running_event: mp.Event):
    logging.info("Network Fetcher Started")
    consumer = Consumer(
        {
            "bootstrap.servers": KAFKA_BROKER,
            "group.id": KAFKA_CONSUMER_GROUP,
            "auto.offset.reset": "latest",
        }
    )
    consumer.subscribe([TOPIC])

    while running_event.is_set():
        msg = consumer.poll(0.1)

        if msg is None or msg.error():
            continue

        raw_bytes = msg.value()

        try:
            header_len = int.from_bytes(raw_bytes[:4], byteorder="big")
            meta_json = raw_bytes[4 : 4 + header_len]
            metadata = json.loads(meta_json)

            img_bytes = raw_bytes[4 + header_len :]
            nparr = np.frombuffer(img_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

            data_queue.put((img, metadata))

        except Exception:
            pass

    consumer.close()


def run_inference_process(data_queue: mp.Queue, running_event: mp.Event):
    logging.info("GPU Inference Started")
    start_http_server(METRICS_PORT)
    avg_conf_gauge = Gauge("batch_avg_confidence", "Model Confidence")
    target_counter = Counter("target_shapes_found", "Blue Squares Found")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    if not os.path.exists(CLASSES_PATH) or not os.path.exists(MODEL_PATH):
        logging.error("Model not found.")
        return

    with open(CLASSES_PATH, "r") as f:
        idx_to_label = json.load(f)
        idx_to_label = {int(k): v for k, v in idx_to_label.items()}

    model = models.mobilenet_v2(weights=None)
    model.classifier[1] = torch.nn.Linear(model.last_channel, len(idx_to_label))
    model.load_state_dict(torch.load(MODEL_PATH, map_location=device))
    model.to(device)
    model.eval()

    preprocess = transforms.Compose(
        [
            transforms.ToPILImage(),
            transforms.Resize(224),
            transforms.ToTensor(),
        ]
    )

    saver = DiscoverySaver()
    batch_imgs = []
    batch_metas = []

    while running_event.is_set():
        try:
            img, meta = data_queue.get(timeout=1.0)
            batch_imgs.append(img)
            batch_metas.append(meta)

            if len(batch_imgs) >= BATCH_SIZE:
                tensors = []
                for b_img in batch_imgs:
                    rgb_img = cv2.cvtColor(b_img, cv2.COLOR_BGR2RGB)
                    tensors.append(preprocess(rgb_img))

                batch_t = torch.stack(tensors).to(device)

                with torch.no_grad():
                    outputs = model(batch_t)
                    probs = torch.nn.functional.softmax(outputs, dim=1)
                    top_conf, top_class_idx = torch.max(probs, dim=1)

                conf_np = top_conf.cpu().numpy()
                idx_np = top_class_idx.cpu().numpy()
                avg_conf_gauge.set(np.mean(conf_np))

                for i, conf in enumerate(conf_np):
                    label = idx_to_label[idx_np[i]]

                    # Debugging
                    # if conf > 0.90:
                    # logging.info(f"Saw '{label}' with {conf:.2f}")
                    # pass

                    # String (class name) matching
                    clean_label = label.strip()

                    is_red_circle = "red_circle" in clean_label

                    if is_red_circle and conf > 0.90:
                        logging.info(f"TARGET MATCH: {clean_label} (Conf: {conf:.2f})")
                        target_counter.inc()
                        saver.save_hit_async(
                            batch_imgs[i], conf, clean_label, batch_metas[i]
                        )

                batch_imgs = []
                batch_metas = []

        except queue.Empty:
            continue

        except Exception as e:
            logging.error(f"Inference Error: {e}")
            batch_imgs = []
            batch_metas = []


def main():
    mp.set_start_method("spawn", force=True)
    data_queue = mp.Queue(maxsize=QUEUE_SIZE)
    running_event = mp.Event()
    running_event.set()

    fetcher = mp.Process(target=fetch_data_process, args=(data_queue, running_event))
    inference = mp.Process(
        target=run_inference_process, args=(data_queue, running_event)
    )

    fetcher.start()
    inference.start()

    try:
        fetcher.join()
        inference.join()

    except KeyboardInterrupt:
        running_event.clear()
        fetcher.terminate()
        inference.terminate()


if __name__ == "__main__":
    main()
