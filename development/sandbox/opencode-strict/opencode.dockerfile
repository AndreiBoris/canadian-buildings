FROM docker/sandbox-templates:opencode
USER root
RUN npm uninstall -g opencode-ai && npm install -g @opencode/cli@2.4.0 --include=optional
RUN mkdir -p /etc/opencode
COPY opencode.json /etc/opencode/opencode.json
RUN chmod 644 /etc/opencode/opencode.json
USER agent
ENTRYPOINT ["opencode"]
CMD []