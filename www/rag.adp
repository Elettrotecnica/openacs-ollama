<master>

  <if @message@ not nil>
    <h1>Your question:</h1>
    <p>@message@</p>
    <h1>Context information:</h1>
    <ul>
      <multiple name="references">
        <li>
          <a title="@references.content@" href="@references.url@">@references.title@ - (@references.similarity@)</a>
        </li>
      </multiple>
    </ul>
    <h1>Reply:</h1>
    <p id="reply"></p>
    <div id="rag-message" style="display:none;">@rag_message@</div>
  </if>
  <formtemplate id="chat"></formtemplate>
