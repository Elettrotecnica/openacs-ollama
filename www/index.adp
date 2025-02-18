<master>
  <property name="doc(title)">Conversations</property>

  <h1>Knowledge Base</h1>
  <ul>
    <multiple name="knowledge">
      <li>
        @knowledge.instance_name@
        -
        <a href="@knowledge.url@">@knowledge.url@</a>
        -
        <include src="/packages/notifications/lib/notification-widget"
                 type="ollama_index_notif"
                 object_id="@knowledge.object_id;literal@"
                 pretty_name="@knowledge.instance_name;literal@ @index_notif_pretty_name;literal@"
                 show_subscribers_p="false"
                 url="@url;literal@">
      </li>
    </multiple>
  </ul>

  <h1>Conversations</h1>
  <listtemplate name="conversations"></listtemplate>
