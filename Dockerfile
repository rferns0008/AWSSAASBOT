FROM python:3.11-slim
RUN groupadd -r flaskuser && useradd -r -g flaskuser flaskuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN chown -R flaskuser:flaskuser /app
USER flaskuser
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]