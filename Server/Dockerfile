ARG SERVERCORE_VERSION=ltsc2019
FROM mcr.microsoft.com/windows/servercore:${SERVERCORE_VERSION}

COPY Scripts/*.* /Scripts/
WORKDIR /Scripts

COPY Server/Scripts/*.* /Scripts/Server/

# add local copy of installers to reduce download
#COPY Server/msi/*.msi /Install/

HEALTHCHECK --interval=20s --timeout=20s --retries=6 CMD powershell -file ./Server/healthcheck-server.ps1

EXPOSE 81
EXPOSE 10943

ARG OctopusVersion
ENV OctopusVersion ${OctopusVersion}
ENV ServerNodeName "OctopusNode1"

LABEL   org.label-schema.schema-version="1.0" \
    org.label-schema.name="Octopus Deploy Server" \
    org.label-schema.vendor="Octopus Deploy" \
    org.label-schema.url="https://octopus.com" \
    org.label-schema.vcs-url="https://github.com/OctopusDeploy/Octopus-Docker" \
    org.label-schema.license="Apache"  \
    org.label-schema.description="Octopus Deploy Server Instance" \
    org.label-schema.build-date=$BUILD_DATE

RUN powershell -File ./Server/build.ps1
ENTRYPOINT ["/Scripts/Server/entrypoint.bat"]
