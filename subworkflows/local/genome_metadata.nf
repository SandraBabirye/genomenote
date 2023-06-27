#!/usr/bin/env nextflow

//
// Fetch genome metadata for genome notes
//

include { RUN_WGET              }       from '../../modules/local/run_wget'
include { PARSE_ENA_ASSEMBLY    }       from '../../modules/local/parse_ena_assembly'
include { PARSE_ENA_BIOPROJECT  }       from '../../modules/local/parse_ena_bioproject'
include { PARSE_ENA_BIOSAMPLE   }       from '../../modules/local/parse_ena_biosample'
include { PARSE_ENA_TAXONOMY    }       from '../../modules/local/parse_ena_taxonomy'
include { PARSE_NCBI_ASSEMBLY   }       from '../../modules/local/parse_ncbi_assembly'
include { PARSE_NCBI_TAXONOMY   }       from '../../modules/local/parse_ncbi_taxonomy'
include { PARSE_GOAT_ASSEMBLY   }       from '../../modules/local/parse_goat_assembly'
include { COMBINE_METADATA      }       from '../../modules/local/combine_metadata'    
include { POPULATE_TEMPLATE     }       from '../../modules/local/populate_template'

workflow GENOME_METADATA {
    take:
    ch_file_list        // channel: /path/to/genome_metadata_file_template
    ch_note_template   // channel: /path/to/genome_note_doc_template

    main:
    ch_versions = Channel.empty()
    ch_combined = Channel.empty()

    // Define channel for RUN_WGET
    ch_file_list
        .splitCsv(header: ['source', 'type', 'url', 'ext'], skip: 1)
        .map { row -> [
            // meta
            [ 
                source: row.source, 
                type: row.type, 
                ext: row.ext, 
            ],
            // url 
            row.url
                .replaceAll(/ASSEMBLY_ACCESSION/, params.assembly)
                .replaceAll(/TAXONOMY_ID/, params.taxon_id)
                .replaceAll(/BIOPROJECT_ACCESSION/, params.bioproject)
                .replaceAll(/BIOSAMPLE_ACCESSION/, params.biosample)
        ] }
        .set{file_list}

    // Fetch files
    RUN_WGET ( file_list ) 

    ch_versions = ch_versions.mix(RUN_WGET.out.versions.first())

    // Change this to branch code to manage passing of downloaded files to the appropriate parsing module    
    //ch_all_files = Channel.empty()
    //.mix( RUN_WGET.out.file_path)



    ch_input = RUN_WGET.out.file_path.branch { 
        ENA_ASSEMBLY: it[0].source == "ENA"  && it[0].type == "Assembly"
        ENA_BIOPROJECT: it[0].source == "ENA"  && it[0].type == "Bioproject"
        ENA_BIOSAMPLE: it[0].source == "ENA"  && it[0].type == "Biosample"
        ENA_TAXONOMY: it[0].source == "ENA"  && it[0].type == "Taxonomy"
        NCBI_ASSEMBLY: it[0].source == "NCBI"  && it[0].type == "Assembly"
        NCBI_TAXONOMY: it[0].source == "NCBI"  && it[0].type == "Taxonomy"
        GOAT_ASSEMBLY: it[0].source == "GOAT"  && it[0].type == "Assembly"
    }

    PARSE_ENA_ASSEMBLY ( ch_input.ENA_ASSEMBLY )
    ch_versions = ch_versions.mix(PARSE_ENA_ASSEMBLY.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_ENA_ASSEMBLY.out.file_path)

    PARSE_ENA_BIOPROJECT ( ch_input.ENA_BIOPROJECT )
    ch_versions = ch_versions.mix(PARSE_ENA_BIOPROJECT.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_ENA_BIOPROJECT.out.file_path)


    PARSE_ENA_BIOSAMPLE ( ch_input.ENA_BIOSAMPLE )
    ch_versions = ch_versions.mix(PARSE_ENA_BIOSAMPLE.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_ENA_BIOSAMPLE.out.file_path)


    PARSE_ENA_TAXONOMY ( ch_input.ENA_TAXONOMY )
    ch_versions = ch_versions.mix(PARSE_ENA_TAXONOMY.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_ENA_TAXONOMY.out.file_path)


    PARSE_NCBI_ASSEMBLY ( ch_input.NCBI_ASSEMBLY )
    ch_versions = ch_versions.mix(PARSE_NCBI_ASSEMBLY.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_NCBI_ASSEMBLY.out.file_path)

    PARSE_NCBI_TAXONOMY ( ch_input.NCBI_TAXONOMY )
    ch_versions = ch_versions.mix(PARSE_NCBI_TAXONOMY.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_NCBI_TAXONOMY.out.file_path)

    PARSE_GOAT_ASSEMBLY ( ch_input.GOAT_ASSEMBLY)
    ch_versions = ch_versions.mix(PARSE_GOAT_ASSEMBLY.out.versions.first())
    ch_combined = ch_combined.concat(PARSE_GOAT_ASSEMBLY.out.file_path)


    
    ch_combined = ch_combined.collect(flat: false)

    COMBINE_METADATA(ch_combined)
    ch_versions = ch_versions.mix(COMBINE_METADATA.out.versions.first())
    COMBINE_METADATA.out.file_path_consistent.set {ch_all_params}
 
    ch_all_params.view()
    
    POPULATE_TEMPLATE(ch_all_params, ch_note_template)
    ch_versions = ch_versions.mix(POPULATE_TEMPLATE.out.versions.first())

    emit:
    versions    = ch_versions.ifEmpty(null) // channel: [versions.yml]
}