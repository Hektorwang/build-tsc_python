# note

## 交叉编译

Docker + QEMU 模拟 + Buildx

### 做透明代理(可选)

### 安装 docker

### 安装 QEMU + binfmt 支持

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

### 启用 Docker Buildx

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx rm mybuilder
docker buildx create --name mybuilder --driver docker-container --use
docker buildx inspect --bootstrap
```

### 使用 buildx 交叉编译

```bash
# 根据核心包列表重新生成 requirements.txt
(
  cd files
  pip-compile requirements.in
)
# Euler
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --progress plain \
    --no-cache=false \
    --cache-to=type=local,dest=./tmp/cache-builder-euler \
    --cache-from=type=local,src=./tmp/cache-builder-euler \
    --build-arg CACHE_BUSTER_GET_MICROMAMBA="$(date +%s)" \
    --target exporter \
    --output type=local,dest=./output/euler/ \
    --file Euler.dockerfile . 2>&1 | tee log/Euler-build.log

# RedHat
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --progress plain \
  --no-cache=false \
  --cache-to=type=local,dest=./tmp/cache-builder-redhat \
  --cache-from=type=local,src=./tmp/cache-builder-redhat \
  --build-arg CACHE_BUSTER_GET_MICROMAMBA="$(date +%s)" \
  --target exporter \
  --output type=local,dest=./output/redhat/ \
  --file RedHat.dockerfile . 2>&1 | tee log/RedHat-build.log

docker buildx build \
  --platform linux/amd64 \
  --progress plain \
  --no-cache=false \
  --cache-to=type=local,dest=./tmp/cache-builder-redhat-amd64 \
  --cache-from=type=local,src=./tmp/cache-builder-redhat \
  --build-arg CACHE_BUSTER_GET_MICROMAMBA="$(date +%s)" \
  --target exporter \
  --output type=local,dest=./output/redhat/ \
  --file RedHat.dockerfile . 2>&1 | tee log/RedHat-build-amd64.log
```
