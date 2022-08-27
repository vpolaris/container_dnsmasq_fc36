# container_dnsmasq_fc36

A dnsmasq container configured for DHCP Proxy by default. you can override default configuration file by adding
--volume $(pwd)/dnmasq.conf:/etc/dnsmasq.conf:rw
