# Custom Iglu Schemas

Schemas pulled from Snowplow BDP for Adobe Commerce storefront events.

## Directory Layout

Follows iglu-compatible convention: `vendor/name/format/version`

```
schemas/
└── com.adobe.magento.entity/
    ├── product/jsonschema/1-0-0
    ├── product/jsonschema/2-0-0
    ├── product/jsonschema/3-0-0
    └── ...
```

## Schema Types

- **entity** (33 schemas) — context attached to events (product, shopper, shopping-cart, etc.)
- **event** (2 schemas) — self-describing events (page_unload, activity-summary)

## Pulling Schemas from BDP

```bash
make pull-schemas
```

Requires `SNOWPLOW_CONSOLE_ORG_ID`, `SNOWPLOW_CONSOLE_API_KEY_ID`, and `SNOWPLOW_CONSOLE_API_KEY` in `.env`. Pulls all versions for each data structure (Iglu Server requires sequential version uploads).

## Uploading to Local Iglu Server

```bash
make upload-schemas
```

Uploads all schemas in version order to the local Iglu Server at `http://localhost:8181`.

## Adding Schemas Manually

1. Create the directory: `schemas/{vendor}/{name}/jsonschema/`
2. Add the schema file named by version (e.g., `1-0-0`) containing the JSON Schema body
3. Run `make upload-schemas`
