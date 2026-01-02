import time
import json
import sys
import os
import random
import cv2
import numpy as np
from confluent_kafka import Producer
from dotenv import load_dotenv
import ast

load_dotenv()

# Config
BOOTSTRAP_SERVER = os.getenv("KAFKA_BOOTSTRAP_SERVER", "localhost:9092")
TOPIC = os.getenv("KAFKA_TOPIC", "image_data")
IMG_HEIGHT = int(os.getenv("IMG_HEIGHT", 512))
IMG_WIDTH = int(os.getenv("IMG_WIDTH", 512))
INTERVAL = float(os.getenv("PRODUCER_INTERVAL", 0.05))
COLORS = {
    "red": ast.literal_eval(os.getenv("COLORS_RED", "(0, 0, 255)")),
    "green": ast.literal_eval(os.getenv("COLORS_GREEN", "(0, 255, 0)")),
}
SHAPES = ast.literal_eval(os.getenv("SHAPES", '["circle", "square"]'))


def create_shape_image():
    # 1. Gray background
    img = np.full((IMG_HEIGHT, IMG_WIDTH, 3), 128, dtype=np.uint8)

    # 2. Random Selection
    shape = random.choice(SHAPES)
    color_name = random.choice(list(COLORS.keys()))
    color = COLORS[color_name]

    # 3. Draw
    center_x, center_y = IMG_WIDTH // 2, IMG_HEIGHT // 2
    size = 150

    if shape == "circle":
        cv2.circle(img, (center_x, center_y), size, color, -1)

    elif shape == "square":
        cv2.rectangle(
            img,
            (center_x - size, center_y - size),
            (center_x + size, center_y + size),
            color,
            -1,
        )

    # elif shape == "triangle":
    #     pts = np.array([
    #         (center_x, center_y - size),
    #         (center_x - size, center_y + size),
    #         (center_x + size, center_y + size)
    #     ])
    #     cv2.drawContours(img, [pts], 0, color, -1)

    return img, shape, color_name


def delivery_report(err, msg):
    if err is not None:
        print(f"Delivery failed: {err}", file=sys.stderr)


def main():
    producer = Producer(
        {"bootstrap.servers": BOOTSTRAP_SERVER, "message.max.bytes": 10485760}
    )

    print(f"Producer Started: {IMG_HEIGHT}x{IMG_WIDTH} | Topic: {TOPIC}")
    print("Generating: Circles, Squares")

    try:
        while True:
            # 1. Generate Visual Data
            image_array, shape, color = create_shape_image()

            # 2. Encode to JPEG (instead of raw float arrays to save bandwidth)
            ret, jpeg_bytes = cv2.imencode(".jpg", image_array)
            if not ret:
                continue

            # 3. Pack Metadata
            metadata = {
                "timestamp": time.time(),
                "shape_label": shape,
                "color_label": color,
                "dtype": "jpeg",
            }

            meta_json = json.dumps(metadata).encode("utf-8")
            header_len = len(meta_json).to_bytes(4, byteorder="big")

            # Payload = [4 bytes Header Size] + [JSON Metadata] + [JPEG Bytes]
            payload = header_len + meta_json + jpeg_bytes.tobytes()

            # 4. Send
            producer.produce(TOPIC, payload, callback=delivery_report)
            producer.poll(0)

            time.sleep(INTERVAL)

    except KeyboardInterrupt:
        print("Stopping producer")

    finally:
        producer.flush()


if __name__ == "__main__":
    main()
