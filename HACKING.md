# Patches

Patches should be submitted in the form of pull requests at
[github][github].

# Coding style

Standard PEP-8 formatting is used project wide for Python, with a few
relaxations, like maximum line length (120). A pylint config file
[`.pylintrc`](.pylintrc) is provided. The `./run-test.sh` will lint
the source code using this (see *Testing* below).

# Testing

## Unit tests

To support local development an container `test/Dockerfile` contains
the environment to test all three plugins. It can be built and run
via `./run-test.sh`. This will execute the unit tests as well as
run `pylint` and ShellCheck on the source code.

## Local integration testing

### Preparation

This assumes that osbuild-composer, version greater than 21, is
installed on the host and the koji API is enabled.

Make certificates for osbuild-composer. This is needed to authorize
clients to use the composer API. There is a script that will create
the certificates and also copy it to the correct places in `/etc`.

```sh
sudo test/make-certs.sh
```

Build the containers:

```sh
sudo test/build-container.sh
```

### Setup the infrastructure containers

Run the infra containers, i.e. the database server, the kerberos kdc,
and koji hub. This will also create the kerberos keytabs needed for
the koji builder to authorize itself to koji hub.

```sh
sudo test/run-koji-container.sh start
```

Koji web will now be running at: http://localhost:8080/koji/


Copy the credentials: The TLS certificates for the koji builder plugin
to make authorize requests to composer and the kerberos keytabs
needed for composer and worker (of composer) to reserve and import the
build via the koji XML RPC.

```sh
sudo  test/copy-creds.sh
```

### Run the koji builder

Run the koji builder instance can be started. Here `fg` means that
it will be running in the foreground, so logs can be inspected and
the container stopped via `ctrl+c`.

```sh
sudo test/run-builder.sh fg
```

Verify we can talk to koji hub via the koji command line client:

```sh
$ koji --server=http://localhost:8080/kojihub --user=osbuild --password=osbuildpass --authtype=password hello
grüezi, osbuild!

You are using the hub at http://localhost:8080/kojihub
Authenticated via password
```

### Setup the tags

In order to build an image, a series of tags needs to be created.
Specifically:

 * the target tag
 * the build tag, which contains the architectures
 * destination tag, which contains the list of packages

A helper script will create a minimum set that is necessary to build
an image call `Fedora-Cloud` for `f33-candidate`:

```sh
test/make-tags.sh
```

### Client plugin

The client plugin needs to be installed either by creating the RPMs
first via meson, or via a symlink from the checkout to the koji cli
plugin directory:

```sh
mkdir -p /usr/lib/python3.8/site-packages/koji_cli_plugins/
ln -s $(pwd)/plugins/cli/osbuild.py \
	  /usr/lib/python3.8/site-packages/koji_cli_plugins/osbuild.py
```

### Making a build

Now that all is setup a build can be created via:

```sh
koji --server=http://localhost:8080/kojihub \
     --user=kojiadmin \
	 --password=kojipass \
	 --authtype=password \
	 osbuild-image \
	 Fedora-Cloud \
	 33 \
	 fedora-33 \
	 f33-candidate \
	 x86_64 \
	 --repo 'http://download.fedoraproject.org/pub/fedora/linux/releases/33/Everything/$arch/os/' \
	 --image-type qcow2 \
	 --release 1
```

### Troubleshooting

Check logs:

```sh
sudo podman logs org.osbuild.koji.koji  # koji hub
sudo podman logs org.osbuild.koji.kdc   # kerberos kdc
```

Execute into the container:

```sh
sudo podman exec -it org.osbuild.koji.koji /bin/bash
sudo podman exec -it org.osbuild.koji.kdc /bin/bash
sudo podman exec -it org.osbuild.koji.kojid /bin/bash
```

### Cleanup

Stopping the container:

```sh
sudo test/run-koji-container.sh stop
```

Cleanup of kerberos tickets:
```sh
sudo kdestroy -A
sudo -u _osbuild-composer kdestroy -A
```

## Useful links

- [koji source](https://pagure.io/koji/tree/master)
- [koji plugin howto](https://docs.pagure.org/koji/writing_a_plugin/)
- [koji server howto](https://docs.pagure.org/koji/server_howto/)
- [koji server bootstrap](https://docs.pagure.org/koji/server_bootstrap/)
- [osbs koji plugin](https://github.com/containerbuildsystem/koji-containerbuild/)

[github][https://github.com/osbuild/koji-osbuild]
