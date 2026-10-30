# Local example

Applies circuit-cinc to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

It writes a small cookbook, `hello`, to `/var/lib/cinc/repo`, installs Cinc Client, converges it once, and sets an hourly timer:

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To see the idempotence for yourself, overwrite the file and converge twice:

```sh
ssh -p 2308 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1
cat /etc/hello-from-cinc
echo tampered > /etc/hello-from-cinc
systemctl start cinc-client
systemctl start cinc-client
journalctl -u cinc-client | grep 'resources updated'
```

The second-to-last line of that output says `1/1 resources updated`, which is the first run putting the file back. The last says `0/1`, which is the second run finding nothing to do.

Change the recipe in `main.circuit.hcl` and apply again, and Conn3x converges again, because the example's `converge_trigger` hashes the cookbook.

`up.sh` listens on `127.0.0.1:2308`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
