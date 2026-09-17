# Combined and bundled outputs

Skald 1.1.0 supports three output modes: Markdown, JSON, and Both. Both runs the established renderer for each format during one conversion run and reports both published output URLs.

The optional **Bundle original with outputs** control changes delivery from loose generated files to one folder per converted input. The folder contains the original input in its existing format and the requested generated files.

| Selection | Bundle contents |
| --- | --- |
| Markdown | Original plus `.md` |
| JSON | Original plus `.json` |
| Both | Original plus `.md` and `.json` |

For `article.pdf`, Both with bundling normally produces:

```text
article-bundle/
├── article.pdf
├── article.md
└── article.json
```

The original filename is retained. If it conflicts with a generated name, the generated file is qualified. For example, an input named `article.md` produces `article.md`, `article-converted.md`, and `article.json`.

Bundle folders are staged beside the final destination and become visible through one exclusive rename only after the source copy and generated outputs are complete. Existing entries are not replaced. Collisions use the source extension and then a numeric suffix, such as `article-pdf-bundle` and `article-pdf-bundle-2`.
