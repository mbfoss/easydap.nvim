-- Java — expects an external debug server (e.g. started by nvim-jdtls). Unlike
-- `remote`, this adapter also wants the JVM's JDWP endpoint echoed into the attach
-- body. com.microsoft.java.debug reads `hostName`/`port` (not `host`); the field
-- set follows microsoft/vscode-java-debug's attach configuration.
---@type easydap.AdapterDef
return {
    host          = "127.0.0.1",
    port          = 0,
    request       = "attach",
    attach_schema = {
        hostName    = { type = "string", kind = "host", desc = "JVM debug (JDWP) host", default = "localhost" },
        port        = { type = "integer", kind = "port", desc = "JVM debug (JDWP) port" },
        timeout     = { type = "integer", desc = "attach timeout in milliseconds", default = 30000 },
        projectName = { type = "string", desc = "project name (helps resolve sources/classpaths)" },
    },
    templates     = {
        -- `host`/`port` fill both the JDWP body fields (hostName/port) and the
        -- task-level connection (this adapter's own def carries host/port, so
        -- it connects to the java-debug server over TCP too).
        remote    = {
            request    = "attach",
            parameters = { hostName = "{host}", port = "{port}" },
            connect    = { host = "{host}", port = "{port}" },
        },
    },
}
