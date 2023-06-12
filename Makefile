all: debianzfs.qcow2

# Generate password
debianzfs.qcow2: export PKR_VAR_password="$(pwgen -s 8 1)"

# Release info
debianzfs.qcow2: export PKR_VAR_release=12.0.0
debianzfs.qcow2: export PKR_VAR_codename=bookworm
debianzfs.qcow2: export PKR_VAR_sha256=fa3960f6f692fc60a43eec4362d60f754b4a246ab64aa662270dd879a946de84

debianzfs.qcow2:
	packer build -color=false . | tee debianzfs.log

clean:
	rm -rf output debianzfs.log
