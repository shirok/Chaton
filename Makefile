GOSH = gosh

all: rooms

rooms:
	@echo "List config files of rooms in the file 'rooms', one per line, then run 'make install'"

install: all
	for r in `cat rooms`; do \
	  $(GOSH) ./build-site $$r; \
	done

check:
	@rm -f test.record test.log
	cd tests; GAUCHE_TEST_RECORD_FILE=../test.record $(MAKE) check
	@cat test.record

clean:
	cd tests; $(MAKE) clean
	if [ -f client/Makefile ]; then cd client; $(MAKE) clean; fi
	rm -rf test.record *.log *~

realclean: clean
	if [ -f client/Makefile ]; then cd client; $(MAKE) realclean; fi

maintainer-clean: clean
	if [ -f client/Makefile ]; then cd client; $(MAKE) maintainer-clean; fi
