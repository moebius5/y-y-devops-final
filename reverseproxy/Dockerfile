FROM openresty/openresty:1.21.4.3-2-bullseye-fat

RUN opm get knyar/nginx-lua-prometheus && \
    mkdir -p /data/nginx/cache

RUN rm -rf /etc/nginx
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx/ /etc/nginx/

EXPOSE 80 443
