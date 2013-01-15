API
===

store
-----

for every file in `tostore/`, compute hash and add "untagged" tag, save MIME and machine identifier

duplicates
----------

find duplicates in storage by hash, merge file names and replace all occurences in the tag history

tags
----

retrieve all file names of files tagged with one or multiple tags

***

internals
---------

data per file
+ name(s)
+ size
+ mime
+ [ machine identifier ]

data per tag
- history (needed for unsynchronized removal of duplicates)
