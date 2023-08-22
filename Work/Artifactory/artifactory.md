# Run to see output
jfrog rt s --spec artifactory_del.spec

# Run to delete based on rules
jfrog rt del --spec artifactory_del.spec

# Run to copy artifact from one repo into another (and maintain same path)
# I.E. artifact below would exist at nexus-mvn-releases/com/hulu/piquet/0.0.5
jfrog rt cp nexus-releases/com/hulu/piquet/0.0.5 nexus-mvn-releases/