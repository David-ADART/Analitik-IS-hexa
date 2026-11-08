FROM python:3.11-slim

WORKDIR /app
COPY servidor.py index.html ./
COPY css ./css
COPY js ./js

ENV PORT=7860
EXPOSE 7860

CMD ["python", "-u", "servidor.py"]
