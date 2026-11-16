FROM neosmemo/memos:stable

ENV MEMOS_MODE=prod \
    MEMOS_DRIVER=postgres \
    MEMOS_PORT=5230 \
    PORT=5230

EXPOSE 5230

# MEMOS_DSN (Neon pooled connection string) must be provided at runtime.
# Neon Object Storage (S3) is configured in Memos Admin UI: Settings > Storage.
