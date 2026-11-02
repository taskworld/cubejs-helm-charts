# Cube's own image plus the npm packages our cube.js needs at runtime.
# Bump the base tag together with charts/cubejs/values.yaml.
FROM cubejs/cube:v1.7.46

# NODE_PATH already includes /cube/conf/node_modules; the chart mounts only
# /cube/conf/model and /cube/conf/cube.js, so this directory stays visible.
RUN npm install --prefix /cube/conf --no-save --no-package-lock ioredis@5.11.1 \
  && node -e "require('ioredis')"
