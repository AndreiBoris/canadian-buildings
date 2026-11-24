FROM docker/sandbox-templates:opencode
USER agent
RUN mkdir -p /home/agent/.config/opencode
COPY --chown=agent:agent opencode.json /home/agent/.config/opencode/opencode.json
ENTRYPOINT ["opencode"]
CMD []