# Stands in for the agent's machine. Built with internet access; run without
# it. Everything it does at runtime goes through leash or nowhere.
FROM node:22-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates python3 python3-pip \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g @anthropic-ai/claude-code \
 && useradd -m -s /bin/bash dev
USER dev
WORKDIR /work
CMD ["sleep", "infinity"]
