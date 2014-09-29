
<%@ page contentType="text/html;charset=UTF-8" %>
<html>
<head>
    <meta name="layout" content="main"/>
    <title>Join the chat?</title>
</head>
<body>
    <div class="nav" role="navigation">
        <ul>
            <li><a class="home" href="${createLink(uri: '/')}"><g:message code="default.home.label"/></a></li>
        </ul>
    </div>

    <br/>

    <g:form name="chat" action="chat" >
        <g:hiddenField name="sessionId" value="${sessionId}" />

        <label for="name">Enter your name: </label>
        <g:textField name="name" required="" />

        <br/>

        <fieldset class="buttons">
            <g:submitButton name="create" class="chat" value="Chat"/>
        </fieldset>

    </g:form>

</body>
</html>