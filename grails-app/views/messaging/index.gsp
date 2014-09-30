
<%@ page contentType="text/html;charset=UTF-8" %>
<html>
<head>
    <meta name="layout" content="main"/>
    <asset:stylesheet href="chat.css"/>

    <title>Join the chat?</title>
</head>
<body>
    <div class="nav" role="navigation">
        <ul>
            <li><a class="home" href="${createLink(uri: '/')}"><g:message code="default.home.label"/></a></li>
        </ul>
    </div>

    <g:form name="chat" action="chat" >
        <g:hiddenField name="chatId" value="${chatId}" />

        <div class="boxed">
            <label for="name">Enter your name: </label>
            <g:textField name="name" required="" />
        </div>

        <fieldset class="buttons">
            <g:submitButton name="create" class="chat" value="Chat"/>
        </fieldset>

    </g:form>

</body>
</html>