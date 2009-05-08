TESTS = lib.scm viewer.scm poster.scm archiver.scm

all:

check:
	for f in $(TESTS); do gosh $$f; done >> ../test.log

clean:
	rm -rf data.o @@server-data-dir@@lock *~

