_Import settings: utf-8, delimiter U+002C, header present._

# Delimited data

Column IDs are stable; labels retain source text. JSON `null` means a missing field; `""` means an explicit empty field. Record objects use the column IDs.

## Columns

~~~json
[{"id":"c1","label":"Name","origin":"header"},{"id":"c2","label":"Notes","origin":"header"}]
~~~

### Record 1 (2 fields)

~~~json
{"c1":"Alpha","c2":"left|right"}
~~~

### Record 2 (2 fields)

~~~json
{"c1":"Beta","c2":"line one\nline two"}
~~~
