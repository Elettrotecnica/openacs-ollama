<master>

  <if @message@ not nil>
    <h1>Your question:</h1>
    <p>@message@</p>
    <h1>Context information:</h1>
    <ul>
      <multiple name="references">
        <li>
          <div id="modal-@references.index_id@" class="acs-modal">
            <div class="acs-modal-content">
              <h3>@references.title@</h3>
              <p>@references.content@</p>
              <p><a href="@references.url@" target="_blank">#acs-subsite.See_full_size#</a></p>
              <p>Similarity: @references.similarity@</p>
              <button class="acs-modal-close">Close</button>
            </div>
          </div>
          <a
            class="acs-modal-open"
            data-target="#modal-@references.index_id@"
            href="#">@references.title@
          </a>
        </li>
      </multiple>
    </ul>
    <h1>Reply:</h1>
    <p id="reply"></p>
    <div id="rag-message" style="display:none;">@rag_message@</div>
  </if>
  <formtemplate id="chat"></formtemplate>
