TESTS = lib.scm viewer.scm entry.scm poster.scm archiver.scm browser.scm badge.scm apilogin.scm

all:

check:
	for f in $(TESTS); do gosh $$f; done >> ../test.log

clean:
	rm -rf data.o @@server-data-dir@@lock *~

