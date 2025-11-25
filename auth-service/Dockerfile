FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py .

# Create a non-root user and switch to it
RUN useradd -m appuser && chown -R appuser /app
USER appuser

EXPOSE 8080
# Use gunicorn for production
CMD ["gunicorn", "--workers=4", "--bind=0.0.0.0:8080", "--log-level=debug", "app:app"]
