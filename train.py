import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import models, transforms
from torch.utils.data import Dataset, DataLoader
import cv2
import numpy as np
import json
import os
from dotenv import load_dotenv
import ast

load_dotenv()

# Config
SAMPLES_PER_CLASS = int(os.getenv("SAMPLES_PER_CLASS", 300))
EPOCHS = int(os.getenv("EPOCHS", 3))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", 8))
IMG_SIZE = int(os.getenv("IMG_SIZE", 512))
CENTER = int(os.getenv("CENTER", 256))
SHAPE_SIZE = int(os.getenv("SHAPE_SIZE", 150))
MODEL_PATH = os.getenv("MODEL_PATH", "model.pth")
CLASSES_PATH = os.getenv("CLASSES_PATH", "classes.json")
COLORS = {
    "red": ast.literal_eval(os.getenv("COLORS_RED", "(0, 0, 255)")),
    "green": ast.literal_eval(os.getenv("COLORS_GREEN", "(0, 255, 0)")),
}
SHAPES = ast.literal_eval(os.getenv("SHAPES", '["circle", "square"]'))

# Label Map
ALL_LABELS = [f"{c}_{s}" for c in COLORS.keys() for s in SHAPES]
LABEL_TO_IDX = {label: i for i, label in enumerate(ALL_LABELS)}
IDX_TO_LABEL = {i: label for label, i in LABEL_TO_IDX.items()}


# Dataset
class SyntheticDatasetGenerator(Dataset):
    def __init__(self, samples_per_class, transform=None):
        self.transform = transform
        self.samples = []

        # Generate balanced sample list: (color_name, shape) for each sample
        for color_name in COLORS.keys():
            for shape in SHAPES:
                for _ in range(samples_per_class):
                    self.samples.append((color_name, shape))

        # Shuffle to mix classes during training
        np.random.shuffle(self.samples)

        print(
            f"Dataset created: {len(ALL_LABELS)} classes x {samples_per_class} samples = {len(self.samples)} total"
        )

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        color_name, shape = self.samples[idx]
        label_idx = LABEL_TO_IDX[f"{color_name}_{shape}"]

        # Generate at 512x512 (Same as Producer)
        img = np.full((IMG_SIZE, IMG_SIZE, 3), 128, dtype=np.uint8)
        color = COLORS[color_name]

        if shape == "circle":
            cv2.circle(img, (CENTER, CENTER), SHAPE_SIZE, color, -1)

        elif shape == "square":
            cv2.rectangle(
                img,
                (CENTER - SHAPE_SIZE, CENTER - SHAPE_SIZE),
                (CENTER + SHAPE_SIZE, CENTER + SHAPE_SIZE),
                color,
                -1,
            )

        # elif shape == "triangle":
        #     pts = np.array([(CENTER, CENTER-SHAPE_SIZE),
        #                     (CENTER-SHAPE_SIZE, CENTER+SHAPE_SIZE),
        #                     (CENTER+SHAPE_SIZE, CENTER+SHAPE_SIZE)])
        #     cv2.drawContours(img, [pts], 0, color, -1)

        # Convert to RGB (Training uses RGB)
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        if self.transform:
            img_tensor = self.transform(img_rgb)
            return img_tensor, label_idx

        return img_rgb, label_idx


def train():
    num_classes = len(ALL_LABELS)

    print(f"Training model: {num_classes} classes, {SAMPLES_PER_CLASS} samples each")
    print(f"Classes: {ALL_LABELS}")

    transform = transforms.Compose(
        [
            transforms.ToPILImage(),
            transforms.Resize(224),
            transforms.ToTensor(),
        ]
    )

    dataset = SyntheticDatasetGenerator(SAMPLES_PER_CLASS, transform=transform)
    dataloader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=True)

    print("Loading MobileNetV2")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = models.mobilenet_v2(weights="DEFAULT")

    for param in model.features.parameters():
        param.requires_grad = False

    model.classifier[1] = nn.Linear(model.last_channel, num_classes)
    model.to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.classifier.parameters(), lr=0.001)

    print(f"Starting training on {device}", flush=True)
    model.train()

    for epoch in range(EPOCHS):
        correct = 0
        total = 0

        for inputs, labels in dataloader:
            inputs, labels = inputs.to(device), labels.to(device)
            optimizer.zero_grad()

            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()

        print(
            f"Epoch {epoch+1}/{EPOCHS} - Acc: {100 * correct / total:.2f}%", flush=True
        )

    print("Saving model")
    torch.save(model.state_dict(), MODEL_PATH)

    with open(CLASSES_PATH, "w") as f:
        json.dump(IDX_TO_LABEL, f)

    print("Done.")


if __name__ == "__main__":
    train()
