FROM openresty/openresty:1.21.4.3-2-bullseye-fat

RUN rm -rf /etc/nginx
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx/ /etc/nginx/

RUN opm get knyar/nginx-lua-prometheus && \
    mkdir -p /data/nginx/cache 

EXPOSE 80 443
