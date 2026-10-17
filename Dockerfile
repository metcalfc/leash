# The gateway. It is the only container on both networks, and the only one
# that ever sees a real credential.
FROM python:3.13-slim
WORKDIR /app
COPY leash policy.json ./
RUN chmod +x leash && useradd -r -u 10001 leash && mkdir -p run && chown leash run
USER leash
EXPOSE 8080
ENTRYPOINT ["./leash", "-c", "policy.json"]
CMD ["serve"]
