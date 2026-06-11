# Build from the repo root so the local ClusterProtocol dependency resolves:
#   docker build -f Relay/Dockerfile -t cluster-relayd .
FROM swift:6.1-jammy AS build
WORKDIR /workspace
COPY Packages ./Packages
COPY Relay ./Relay
RUN swift build --package-path Relay -c release --product cluster-relayd

FROM swift:6.1-jammy-slim
COPY --from=build /workspace/Relay/.build/release/cluster-relayd /usr/local/bin/cluster-relayd
EXPOSE 7600/tcp 7601/udp
USER nobody
ENTRYPOINT ["cluster-relayd"]
