FROM python:3.6-slim

RUN apt-get clean \
    && apt-get -y update

RUN apt-get -y install \
    nginx \
    python3-dev \
    build-essential \
    default-libmysqlclient-dev

RUN python3 -m pip install --upgrade pip
RUN python3 -m pip install --upgrade setuptools

WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN pip install -r requirements.txt --src /usr/local/src

COPY . .

EXPOSE 5000
CMD [ "python", "stamps-app.py" ]

