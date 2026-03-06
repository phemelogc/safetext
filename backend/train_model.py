# model training script for smishing detection
import pandas as pd
import joblib

from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.naive_bayes import MultinomialNB
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score

from utils import preprocess_text


import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Load dataset
data_path = os.path.join(BASE_DIR, "data", "SMSSpamCollection")
data = pd.read_csv(
    data_path,
    sep="\t",
    names=["label", "message"]
)

data["label"] = data["label"].map({"ham": 0, "spam": 1})

print("Class distribution:")
print(data["label"].value_counts())


# Preprocess text
data["cleaned_message"] = data["message"].apply(preprocess_text)
data = data[data["cleaned_message"].str.len() > 0]


# TF-IDF vectorization
vectorizer = TfidfVectorizer(max_features=5000)
X = vectorizer.fit_transform(data["cleaned_message"])
y = data["label"]


# Train / test split
X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.2,
    random_state=42,
    stratify=y
)


def train_and_evaluate(model, name):
    model.fit(X_train, y_train)
    preds = model.predict(X_test)

    print(f"\n{name}")
    print(f"Accuracy : {accuracy_score(y_test, preds):.4f}")
    print(f"Precision: {precision_score(y_test, preds):.4f}")
    print(f"Recall   : {recall_score(y_test, preds):.4f}")
    print(f"F1-score : {f1_score(y_test, preds):.4f}")

    return model


# Models
lr_model = train_and_evaluate(
    LogisticRegression(
        max_iter=1000,
        class_weight="balanced",
        random_state=42
    ),
    "Logistic Regression"
)

nb_model = train_and_evaluate(
    MultinomialNB(),
    "Naive Bayes"
)


# Quick manual test
test_message = "Hello Phemelo how are you"
cleaned = preprocess_text(test_message)
vector = vectorizer.transform([cleaned])

print("\nTest message prediction (1 = spam):",
      lr_model.predict(vector)[0])


# Save final model (Logistic Regression)
models_dir = os.path.join(BASE_DIR, "models")
os.makedirs(models_dir, exist_ok=True)
joblib.dump(lr_model, os.path.join(models_dir, "smishing_model.pkl"))
joblib.dump(vectorizer, os.path.join(models_dir, "tfidf_vectorizer.pkl"))

print("\nModel and vectorizer saved successfully.")
