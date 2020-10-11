---
# Feel free to add content and custom Front Matter to this file.
# To modify the layout, see https://jekyllrb.com/docs/themes/#overriding-theme-defaults

layout: default
---

{% for post in site.posts %}
# [{{ post.title }}]({{ site.baseurl }}{{ post.url }})
**{{ post.date | date_to_string }}** tags: {{ post.tags | join: ', ' }}

{% endfor %}
