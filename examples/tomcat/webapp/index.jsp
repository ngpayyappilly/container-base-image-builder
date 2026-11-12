<%@ page contentType="text/plain; charset=UTF-8" session="false" %>hello from tomcat <%= application.getServerInfo() %> on java <%= Runtime.version() %>, user=<%= System.getProperty("user.name") %>
