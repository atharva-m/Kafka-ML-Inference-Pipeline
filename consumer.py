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
from datetime import datetime
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
CONFIDENCE_THRESHOLD = float(os.getenv("CONFIDENCE_THRESHOLD", 0.90))
MAX_STORED_FILES = int(os.getenv("MAX_STORED_FILES", 100))

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO
)


class DiscoverySaver:
    def __init__(self, max_files=MAX_STORED_FILES):
        os.makedirs(STORAGE_PATH, exist_ok=True)
        self.max_files = max_files

        try:
            self.client = MongoClient(MONGO_URI)
            self.db = self.client[DB_NAME]
            self.collection = self.db["shapes_found"]
            logging.info("Connected to MongoDB.")
        except Exception as e:
            self.client = None
            logging.warning(f"MongoDB connection failed: {e}. Running in offline mode.")

        self.executor = ThreadPoolExecutor(max_workers=4)

    def cleanup_storage(self):
        """Deletes oldest files if folder exceeds limit."""
        try:
            files = [
                os.path.join(STORAGE_PATH, f)
                for f in os.listdir(STORAGE_PATH)
                if f.endswith(".jpg") and os.path.exists(os.path.join(STORAGE_PATH, f))
            ]

            if len(files) > self.max_files:
                files.sort(
                    key=lambda x: os.path.getctime(x) if os.path.exists(x) else 0
                )
                num_to_remove = len(files) - self.max_files

                for i in range(num_to_remove):
                    try:
                        if os.path.exists(files[i]):
                            os.remove(files[i])
                    except (OSError, FileNotFoundError):
                        pass
        except Exception:
            pass  # Ignore cleanup errors

    def save_hit_async(self, image_array, confidence, predicted_label, metadata):
        self.executor.submit(
            self._save_task, image_array, confidence, predicted_label, metadata
        )

    def _save_task(self, image_array, confidence, predicted_label, metadata):
        try:
            unique_id = str(uuid.uuid4())
            filename = f"hit_{unique_id}.jpg"
            filepath = os.path.join(STORAGE_PATH, filename)

            cv2.imwrite(filepath, image_array)
            self.cleanup_storage()

            ground_truth_str = f"{metadata.get('color_label', 'unknown')}_{metadata.get('shape_label', 'unknown')}"

            if self.client:
                doc = {
                    "_id": unique_id,
                    "timestamp": datetime.now().isoformat(),
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
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logging.info(f"Inference Started (Device: {device})")

    start_http_server(METRICS_PORT)
    avg_conf_gauge = Gauge("batch_avg_confidence", "Model Confidence")
    target_counter = Counter("target_shapes_found", "High Confidence Detections")

    # Wait for model if not ready
    if not os.path.exists(CLASSES_PATH) or not os.path.exists(MODEL_PATH):
        logging.warning("Model/Classes not found. Waiting for training to complete...")
        while running_event.is_set() and (
            not os.path.exists(CLASSES_PATH) or not os.path.exists(MODEL_PATH)
        ):
            time.sleep(2)
        if not running_event.is_set():
            return

    with open(CLASSES_PATH, "r") as f:
        idx_to_label = json.load(f)
        idx_to_label = {int(k): v for k, v in idx_to_label.items()}

    model = models.mobilenet_v2(weights=None)
    model.classifier[1] = torch.nn.Linear(model.last_channel, len(idx_to_label))
    model.load_state_dict(
        torch.load(MODEL_PATH, map_location=device, weights_only=True)
    )
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
                avg_conf_gauge.set(float(np.mean(conf_np)))

                for i, conf in enumerate(conf_np):
                    label = idx_to_label[idx_np[i]]
                    clean_label = label.strip()

                    # Save ALL high-confidence detections
                    if conf > CONFIDENCE_THRESHOLD:
                        logging.info(f"MATCH: {clean_label} (Conf: {conf:.2f})")
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
        logging.info("Shutting down...")
        running_event.clear()
        fetcher.terminate()
        inference.terminate()


if __name__ == "__main__":
    main()
