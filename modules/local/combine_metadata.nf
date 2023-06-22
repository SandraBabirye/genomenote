process COMBINE_METADATA {
    label 'process_single'

    conda "conda-forge::python=3.9.1"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1' :
        'quay.io/biocontainers/python:3.9--1' }"

    input:
        val(test)

    output:
    path("consistent.csv") , emit:  file_path_consistent
    path("inconsistent.csv") , emit:  file_path_inconsistent
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = []
    for (item in  test){
        def meta = item[0]
        def file = item[1]
        def arg = "--${meta.source}_${meta.type}_file".toLowerCase()
        args.add(arg)
        args.add(file)
    }

    """
    echo ${args.join(" ")}

    combine_parsed_data.py \\
    ${args.join(" ")} \\
    --out_consistent consistent.csv \\
    --out_inconsistent inconsistent.csv


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        combine_parsed_data.py: \$(combine_parsed_data.py --version | cut -d' ' -f2)
    END_VERSIONS
    """
}
