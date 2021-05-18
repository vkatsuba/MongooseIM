## Module Description

This module implements simple `Hacker News Aggregator` based on [API](https://github.com/HackerNews/API).

## Options

Defines endpoint for get `topstories`.

### `modules.mod_hacker_news.topstories_url`
* **Syntax:** string
* **Default:** `"https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"`
* **Example:** `topstories_url = "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"`

Used for control size of `topstories`.

### `modules.mod_hacker_news.topstories_total`
* **Syntax:** positive integer
* **Default:** `50`
* **Example:** `topstories_total = 50`

Defines the interval of getting last `topstories_interval`.

### `modules.mod_hacker_news.topstories_interval`
* **Syntax:** positive integer (milliseconds)
* **Default:** `3000`
* **Example:** `topstories_interval = 3000`

Defines provide control of repeat retry for case if `hacker-news.firebaseio.com` is not available.

### `modules.mod_hacker_news.topstories_retry`
* **Syntax:** positive integer
* **Default:** `10`
* **Example:** `topstories_retry = 10`


## Example Configuration

```toml
[modules.mod_hacker_news]
  topstories_url = "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"
  topstories_total = 50
  topstories_interval = 3000
  topstories_retry = 10
```

## Metrics

If you'd like to learn more about metrics in MongooseIM, please visit [MongooseIM metrics](../operation-and-maintenance/MongooseIM-metrics.md) page.

| Name | Type | Description (when it gets incremented) |
| ---- | ---- | -------------------------------------- |
| ``[Host, mod_hacker_news, get_topstories_response]`` | spiral | Responds for get topstories. |
