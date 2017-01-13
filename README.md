                       WAFP
            (c) Richard Sammet (e-axe)
              http://mytty.org/wafp/


INTRODUCTION
------------
WAFP is a Web Application Finger Printer written in ruby using a SQLite3 DB.

How it works?
--
WAFP fetches the files given by the Finger Prints from a webserver and
checks if the checksums of those files are matching to the given checksums from the
Finger Prints. This way it is able to detect the detailed version and
even the build number of a Web Application.

In detail?
--
A Web Application Finger Print consits of a set of relative file locations
in conjunction with their md5sums. It is made based on a production or example
installation of a Web Application or just out of an extracted Web Application
install files tarball. For this task, generate_wafp_fingerprint.sh is to be used.


REQUIREMENTS (to be clarified)
------------
ruby >= 1.8
sqlite3 >= 3
sqlite3-ruby >= 1.2.4


COMPILE AND INSTALL
-------------------
not needed.


EXAMPLES
--------
./wafp.rb http://www.example.com/
./wafp.rb -p 'wordpress' -v '2%' http://blog.example.com/
./wafp.rb -f -t 32 -s phpmy-save01 -p 'phpmyadmin' -v '1.1.%' https://user:pass@www.example.com/phpmyadmin/
./wafp.rb -d phpmy-save01 -p 'phpmyadmin' -v '1.1.%'

try it, you will see it is as easy as 1,2,3 ;)

AND - take a look at the HOWTO for more scenarios


BUGS & FEATURES
---------------
drop me a line (or multiple) to
richard[tod]sammet[ta]gmail[tod]com

-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2.0.9 (GNU/Linux)

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
AKCXdZdSbpFPLJny+S7CKQ13CaVL7A==
=+atq
-----END PGP PUBLIC KEY BLOCK-----
