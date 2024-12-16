<master>

  <multiple name="messages">
    <h1><if @messages.role@ eq "user">You</if><else>LLM</else>:</h1>
    <p>@messages.content@</p>
    @messages.rag;noquote@
    <hr>
  </multiple>
  <if @message@ ne "">
    <h1>LLM:</h1>
    <div id="rag-message" style="display:none;">@rag_message@</div>
    <p id="reply"></p>
  </if>
  <h1>You:</h1>
  <formtemplate id="chat"></formtemplate>
