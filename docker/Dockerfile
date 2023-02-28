FROM python:alpine3.17

RUN apk update

WORKDIR /app
COPY . /app

RUN pip --no-cache-dir install -r requirements.txt

CMD ["python", "src/app.py"]