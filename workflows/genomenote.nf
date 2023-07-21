/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowGenomenote.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.lineage_db, params.fasta ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.assembly && params.taxon_id && params.bioproject && params.biosample) { metadata_inputs = [ params.assembly, params.taxon_id, params.bioproject, params.biosample ] }
else { exit 1, 'Metadata input not specified. Please include an assembly accession, a taxon id, a bioproject accession and a biosample_accession' }
if (params.input)     { ch_input = Channel.fromPath(params.input) } else { exit 1, 'Input samplesheet not specified!' }
if (params.fasta)     { ch_fasta = Channel.fromPath(params.fasta) } else { exit 1, 'Genome fasta not specified!' }
if (params.binsize)   { ch_bin   = Channel.of(params.binsize)     } else { exit 1, 'Bin size for cooler/cload not specified!' }
if (params.kmer_size) { ch_kmer  = Channel.of(params.kmer_size)   } else { exit 1, 'Kmer library size for fastk not specified' }

// Check optional parameters
if (params.lineage_db) { ch_busco = Channel.fromPath(params.lineage_db) } else { ch_busco = Channel.empty() }


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_metdata_input           = Channel.of( metadata_inputs )
ch_file_list               = Channel.fromPath("$projectDir/assets/genome_metadata_template.csv")
ch_note_template           = Channel.fromPath("$projectDir/assets/genome_note_template.docx")    
ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK       } from '../subworkflows/local/input_check'
include { GENOME_METADATA   } from '../subworkflows/local/genome_metadata'
include { CONTACT_MAPS      } from '../subworkflows/local/contact_maps'
include { GENOME_STATISTICS } from '../subworkflows/local/genome_statistics'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { GUNZIP                      } from '../modules/nf-core/gunzip/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { MULTIQC                     } from '../modules/nf-core/multiqc/main'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []

workflow GENOMENOTE {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in template of data files to fetch, parse these files and output a list of genome metadata params
    GENOME_METADATA ( ch_file_list, ch_note_template )
    ch_versions = ch_versions.mix(GENOME_METADATA.out.versions)

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK ( ch_input ).data
    | branch { meta, file ->
        hic : meta.datatype == 'hic'
            return [ meta, file, [] ]
        pacbio : meta.datatype == 'pacbio'
            return [ meta, file ]
    }
    | set { ch_inputs }
    ch_versions = ch_versions.mix ( INPUT_CHECK.out.versions )


    //
    // MODULE: Uncompress fasta file if needed
    //
    ch_fasta
    | map { file -> [ [ 'id': file.baseName.tokenize('.')[0..1].join('.') ], file ] }
    | set { ch_genome }

    if ( params.fasta.endsWith('.gz') ) {
        ch_fasta    = GUNZIP ( ch_genome ).gunzip
        ch_versions = ch_versions.mix ( GUNZIP.out.versions.first() )
    } else {
        ch_fasta    = ch_genome
    }


    //
    // SUBWORKFLOW: Create contact map matrices from HiC alignment files
    //
    CONTACT_MAPS ( ch_fasta, ch_inputs.hic, ch_bin )
    ch_versions = ch_versions.mix ( CONTACT_MAPS.out.versions )


    //
    // SUBWORKFLOW: Create genome statistics table
    //
    ch_inputs.hic
    | map{ meta, cram, blank ->
        flagstat = file( cram.resolveSibling( cram.baseName + ".flagstat" ), checkIfExists: true )
        [ meta, flagstat ]
    }
    | set { ch_flagstat }

    GENOME_STATISTICS ( ch_fasta, ch_busco, ch_inputs.pacbio, ch_flagstat )
    ch_versions = ch_versions.mix ( GENOME_STATISTICS.out.versions )


    //
    // MODULE: Combine different versions.yml
    //
    CUSTOM_DUMPSOFTWAREVERSIONS ( ch_versions.unique().collectFile(name: 'collated_versions.yml') )


    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowGenomenote.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    methods_description    = WorkflowGenomenote.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description)
    ch_methods_description = Channel.value(methods_description)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(ch_flagstat.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(GENOME_STATISTICS.out.multiqc.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )
    multiqc_report = MULTIQC.out.report.toList()

}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.IM_notification(workflow, params, summary_params, projectDir, log)
    }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
