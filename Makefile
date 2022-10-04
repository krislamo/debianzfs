all: debianzfs.qcow2

debianzfs.qcow2: export PKR_VAR_password = "$(pwgen -s 8 1)"
debianzfs.qcow2:
	packer build -color=false . | tee debianzfs.log

clean:
	rm -rf output debianzfs.log
