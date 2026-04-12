# OpenIM Kylin 2303 Offline Deployment Bundle

Extract this bundle into `/mnt/im` on the target server.

Expected layout:

```text
/mnt/im/install-openim-kylin.sh
/mnt/im/deploy.env
/mnt/im/templates/
/mnt/im/installers/get-docker.sh
/mnt/im/installers/docker-compose-linux-x86_64
/mnt/im/rpms/*.rpm
/mnt/im/images/openim-kylin2303-images-20260411-amd64.tar.gz
```

Recommended steps:

1. Extract the deployment bundle into `/mnt/im`.
2. Create `/mnt/im/images`, `/mnt/im/installers`, and `/mnt/im/rpms`.
3. Upload the Docker image package to `/mnt/im/images/`.
4. Upload offline installer files to `/mnt/im/installers/`.
5. If needed, upload local RPM packages to `/mnt/im/rpms/`.
6. Run the installer.

Commands:

```bash
cd /mnt/im
chmod +x install-openim-kylin.sh
./install-openim-kylin.sh
```

The installer will:

- install Docker from the Internet when needed
- install Nginx from the Internet when needed
- prefer local installer files under `/mnt/im/installers`
- prefer local RPM packages under `/mnt/im/rpms`
- load Docker images from `/mnt/im/images`
- generate runtime configs for `open-im-server` and `openim-chat`
- start the containers with Docker Compose
- publish the services through host Nginx

Default public URLs:

- `http://59.46.214.114:18080/api`
- `http://59.46.214.114:18080/chat`
- `ws://59.46.214.114:18080/msg_gateway`
- `http://59.46.214.114:18080/minio`

If you want to enable TLS later, edit `deploy.env`:

- `ENABLE_TLS=1`
- `PUBLIC_HTTPS_PORT=9443`
- `SSL_CERT_FILE=/path/to/fullchain.pem`
- `SSL_KEY_FILE=/path/to/privkey.pem`
