GOSH = /home/shiro/bin/gosh

all: rooms

rooms:
	@echo "List config files of rooms in the file 'rooms', one per line, then run 'make install'"

install: all
	for r in `cat rooms`; do \
	  $(GOSH) ./build-site $$r; \
	done

check:
	cd tests; $(GOSH) ./poster.scm

clean:
	rm -rf core *.log *~ tests/data.o tests/*~
