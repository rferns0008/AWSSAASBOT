FROM python:3.11-slim
RUN groupadd -r flaskuser && useradd -r -g flaskuser flaskuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir -r requirements.txt --force-reinstall
# This fails the build if httpx is below 0.27.0
RUN python3 -c "import httpx; from packaging import version; \
    assert version.parse(httpx.__version__) >= version.parse('0.27.0'), \
    f'ERROR: httpx version {httpx.__version__} is too old!'"
COPY app.py .
RUN chown -R flaskuser:flaskuser /app
USER flaskuser
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]