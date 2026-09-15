_Import settings: utf-8, delimiter U+002C, header present._

# Delimited data

Column IDs are stable; labels retain source text. JSON `null` means a missing field; `""` means an explicit empty field. Record objects use the column IDs.

## Columns

~~~json
[{"id":"c1","label":"Name","origin":"header"},{"id":"c2","label":"Role","origin":"header"},{"id":"c3","label":"Location","origin":"header"}]
~~~

### Record 1 (3 fields)

~~~json
{"c1":"Ava","c2":"Engineer","c3":"Austin"}
~~~

### Record 2 (3 fields)

~~~json
{"c1":"Miles","c2":"Designer","c3":"Chicago"}
~~~
