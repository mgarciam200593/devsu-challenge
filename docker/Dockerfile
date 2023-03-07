FROM python:alpine3.17

RUN apk update

WORKDIR /app
COPY . /app

RUN pip --no-cache-dir install pytest
RUN pip --no-cache-dir install -r requirements.txt

EXPOSE 5000

CMD ["python", "src/app.py"]