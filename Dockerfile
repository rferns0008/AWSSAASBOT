FROM python:3.11-slim

WORKDIR /app

# 🔥 CRITICAL: Copy requirements FIRST
COPY requirements.txt .

# 🔥 Force fresh dependency install
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code AFTER dependencies
COPY . .

# Ensure correct permissions (optional but good)
RUN useradd -m flaskuser
USER flaskuser

EXPOSE 5000

CMD ["gunicorn", "-b", "0.0.0.0:5000", "app:app"]