import yaml
import os

from snakemake.utils import min_version
from pipeline.bicleaner import packs


min_version("6.6.1")

# `include` directive is not supported by Pycharm plugin, moving all rules to one file to enable live checks
# https://github.com/JetBrains-Research/snakecharm/issues/195


### configuration

container: 'Singularity.sif'

install_deps = config['deps'] == 'true'
data_root_dir = config['root']
cuda_dir = config['cuda']
gpus_num = config['gpus']
workspace = config['workspace']

# experiment
src = config['experiment']['src']
trg = config['experiment']['trg']
experiment = config['experiment']['name']

mono_max_sent_src = config['experiment']['mono-max-sentences-src']
mono_max_sent_trg = config['experiment']['mono-max-sentences-trg']
bicl_default_threshold = config['experiment']['bicleaner']['default-threshold']
bicl_dataset_thresholds = config['experiment']['bicleaner']['dataset-thresholds']
backward_pretrained = config['experiment']['backward-model']

experiment_dir=f"{data_root_dir}/experiments/{src}-{trg}/{experiment}"

# training
training_args = {}
if 'training' in config:
    training_args = {name: ' '.join([f'--{k} {v}' for k,v in conf.items() ])
                     for name, conf in config['training'].items()}

# datasets
train_datasets = config['datasets']['train']
valid_datasets = config['datasets']['devtest']
eval_datasets = config['datasets']['test']
mono_src_datasets = config['datasets']['mono-src']
mono_trg_datasets = config['datasets']['mono-trg']

mono_datasets = {src: mono_src_datasets, trg: mono_trg_datasets}
mono_max_sent = {src: mono_max_sent_src, trg: mono_max_sent_trg}

# parallelization
gpus = ' '.join([str(n) for n in range(int(gpus_num))])
ensemble = list(range(config['experiment']['teacher-ensemble']))
split_length = config['experiment']['split-length']

# logging
log_dir = f"{data_root_dir}/logs/{src}-{trg}/{experiment}"
reports_dir = f"{data_root_dir}/reports/{src}-{trg}/{experiment}"

# binaries
cwd = os.getcwd()
marian_dir = f'{cwd}/3rd_party/marian-dev/build'
kenlm = f'{cwd}/3rd_party/kenlm'
fast_align_build = f'{cwd}/3rd_party/fast_align/build'
extract_lex_build = f'{cwd}/3rd_party/extract-lex/build'
bin = f'{cwd}/bin'

# data
data_dir = f"{data_root_dir}/data/{src}-{trg}/{experiment}"
clean = f"{data_dir}/clean"
biclean = f"{data_dir}/biclean"
cache_dir = f"{data_dir}/cache"
original = f"{data_dir}/original"
translated = f"{data_dir}/translated"
augmented = f"{data_dir}/augmented"
merged = f"{data_dir}/merged"
filtered = f'{data_dir}/filtered'
align_dir = f"{data_dir}/alignment"

# models
models_dir = f"{data_root_dir}/models/{src}-{trg}/{experiment}"
teacher_dir = f"{models_dir}/teacher"
student_dir = f"{models_dir}/student"
student_finetuned_dir = f"{models_dir}/student-finetuned"
speed = f"{models_dir}/speed"
exported = f"{models_dir}/exported"
best_model = f"model.npz.best-{config['experiment']['best-model']}.npz"
backward = f'{models_dir}/backward'

#evaluation
eval_data = f"{original}/eval"
eval_res = f"{models_dir}/evaluation"
eval_backward = f'{eval_res}/backward'
eval_student = f'{eval_res}/student',
eval_student_finetuned = f'{eval_res}/student-finetuned',
eval_speed = f'{eval_res}/speed',
eval_teacher_ens = f'{eval_res}/teacher-ensemble',
full_eval_datasets = expand(f'{eval_data}/{{dataset}}.{{lang}}.gz', dataset=eval_datasets, lang=[src,trg])

# set common environment variables
envs = f'''SRC={src} TRG={trg} MARIAN="{marian_dir}" GPUS="{gpus}" WORKSPACE={workspace} \
BIN="{bin}" DATA_ROOT_DIR="{data_root_dir}" \
CUDA_DIR="{cuda_dir}"'''

### workflow options

results = [f'{exported}/model.{src}{trg}.intgemm.alphas.bin.gz',
           f'{exported}/lex.50.50.{src}{trg}.s2t.bin.gz',
           f'{exported}/vocab.{src}{trg}.spm.gz',
           f'{experiment_dir}/config.yml',
           expand(f'{eval_res}/teacher{{ens}}',ens=ensemble),
           f'{eval_res}/student',
           f'{eval_res}/student-finetuned',
           f'{eval_res}/speed'
           ]

if len(ensemble) > 1:
    results.append(f'{eval_res}/teacher-ensemble')

if install_deps:
    results.append("/tmp/flags/setup.done")

if not backward_pretrained:
    # don't evaluate pretrained model
    results.append(eval_backward)
    train_backward=True
else:
    train_backward = False
    backward = backward_pretrained

# bicleaner

bicleaner_type = packs.find(src, trg)
bicleaner_env = "envs/bicleaner-ai.yml" if bicleaner_type == 'bicleaner-ai' else 'envs/bicleaner.yml'

if bicleaner_type:
    clean_corpus_prefix = f'{biclean}/corpus'
    teacher_corpus = f'{biclean}/corpus'
    use_bicleaner = True
else:
    clean_corpus_prefix = f'{clean}/corpus'
    teacher_corpus = f'{clean}/corpus'
    use_bicleaner = False

clean_corpus_src = f'{clean_corpus_prefix}.{src}.gz'
clean_corpus_trg = f'{clean_corpus_prefix}.{trg}.gz'


# augmentation

if mono_trg_datasets:
    teacher_corpus = f'{augmented}/corpus'
    augment_corpus = True
    continue_teacher = True # continue training on parallel corpus
    teacher_all_output = 'model.npz'
else:
    augment_corpus = False
    continue_teacher = False
    teacher_all_output = best_model


### rules

def find_parts(wildcards, checkpoint):
    checkpoint_output = checkpoint.get(**wildcards).output[0]
    return glob_wildcards(os.path.join(checkpoint_output,"file.{part,\d+}")).part

def dataset_norm(name: str):
    return name.replace('/','_')

shell.prefix(f"{envs} ")

rule all:
    input: results

localrules: experiment
ruleorder: teacher_all > eval_teacher

rule experiment:
    message: "Saving experiment metadata"
    output: f'{experiment_dir}/config.yml'
    priority: 100
    run:
        os.makedirs(experiment_dir, exist_ok=True)
        with open(f'{experiment_dir}/config.yml', 'w') as f:
            yaml.dump(config, f)

# setup

if install_deps:
    rule setup:
        message: "Installing dependencies"
        log: f"{log_dir}/install-deps.log"
        conda: "envs/base.yml"
        priority: 99
        group: 'setup'
        output: touch("/tmp/flags/setup.done")  # specific to local machine
        shell: 'bash pipeline/setup/install-deps.sh >> {log} 2>&1'

rule marian:
    message: "Compiling marian"
    log: f"{log_dir}/compile-marian.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'setup'
    output: trainer=protected(f"{marian_dir}/marian"),decoder=protected(f"{marian_dir}/marian-decoder"),
        scorer=protected(f"{marian_dir}/marian-scorer"),vocab=protected(f'{marian_dir}/spm_train'),
        converter=protected(f'{marian_dir}/marian-conv')
    shell: 'bash pipeline/setup/compile-marian.sh {threads} >> {log} 2>&1'

rule fast_align:
    message: "Compiling fast align"
    log: f"{log_dir}/compile-fast-align.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'setup'
    output: fast_align=protected(f"{bin}/fast_align"), atools=protected(f"{bin}/atools")
    shell: 'bash pipeline/setup/compile-fast-align.sh {fast_align_build} {threads}  >> {log} 2>&1'

rule extract_lex:
    message: "Compiling fast align"
    log: f"{log_dir}/compile-extract-lex.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'setup'
    output: protected(f"{bin}/extract_lex")
    shell: 'bash pipeline/setup/compile-extract-lex.sh {extract_lex_build} {threads} >> {log} 2>&1'

# data downloading

rule download_corpus:
    message: "Downloading parallel corpus"
    log: f"{log_dir}/download_corpus/{{kind}}/{{dataset}}.log"
    conda: "envs/base.yml"
    threads: 1
    group: 'data'
    cache: False # caching is broken in snakemake
    wildcard_constraints: kind="corpus|devset|eval"
    output: multiext(f"{original}/{{kind}}/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    params: prefix=f"{original}/{{kind}}/{{dataset}}", dataset="{dataset}"
    shell: 'bash pipeline/data/download-corpus.sh "{params.dataset}" "{params.prefix}"  >> {log} 2>&1'

rule download_mono:
    message: "Downloading monolingual dataset"
    log: f"{log_dir}/download_mono/{{dataset}}.{{lang}}.log"
    conda: "envs/base.yml"
    threads: 1
    group: 'data'
    cache: False # caching is broken in snakemake
    wildcard_constraints: lang=f"{src}|{trg}"
    output: f'{original}/mono/{{dataset}}.{{lang}}.gz'
    params: max_sent=lambda wildcards: mono_max_sent[wildcards.lang], dataset='{dataset}', lang='{lang}'
    shell: '''bash pipeline/data/download-mono.sh \
                "{params.dataset}" {params.lang} {params.max_sent} "{output}"  >> {log} 2>&1'''

# cleaning

rule clean_corpus:
    message: "Cleaning dataset"
    log: f"{log_dir}/clean_corpus/{{dataset}}.log"
    conda: "envs/base.yml"
    group: "clean_corpus"
    threads: workflow.cores
    input: multiext(f"{original}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    output: multiext(f"{clean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    params: prefix_input=f"{original}/corpus/{{dataset}}",prefix_output=f"{clean}/corpus/{{dataset}}",
            dataset=lambda wildcards: dataset_norm(wildcards.dataset)
    shell: '''bash pipeline/clean/clean-corpus.sh "{params.prefix_input}" "{params.prefix_output}" {threads} {params.dataset} \
                >> {log} 2>&1'''

rule clean_mono:
    message: "Cleaning monolingual dataset"
    log: f"{log_dir}/clean_mono/{{dataset}}.{{lang}}.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    group: "clean_mono{lang}"
    cache: False
    wildcard_constraints: lang=f"{src}|{trg}"
    input: f'{original}/mono/{{dataset}}.{{lang}}.gz'
    output: f'{clean}/mono/{{dataset}}.{{lang}}.gz'
    params: prefix_input=f"{original}/mono/{{dataset}}", prefix_output=f"{clean}/mono/{{dataset}}",
            dataset=lambda wildcards: dataset_norm(wildcards.dataset)
    shell: '''bash pipeline/clean/clean-mono.sh {wildcards.lang} "{params.prefix_input}" "{params.prefix_output}" \
                {threads} {params.dataset} >> {log} 2>&1'''

if use_bicleaner:
    rule kenlm:
        message: "Installing kenlm"
        log: f"{log_dir}/kenlm.log"
        conda: bicleaner_env
        threads: 4
        group: 'setup'
        output: directory(f"{bin}/kenlm")
        shell: 'bash pipeline/setup/install-kenlm.sh {kenlm} {threads}  >> {log} 2>&1'

    rule bicleaner_pack:
        message: f"Downloading language pack for bicleaner"
        log: f"{log_dir}/bicleaner_pack.log"
        conda: bicleaner_env
        group: "clean_corpus"
        threads: 1
        input: rules.kenlm.output
        output: directory(f"{biclean}/pack")
        shell: '''bash pipeline/bicleaner/download-pack.sh "{output}" {bicleaner_type} >> {log} 2>&1'''

    rule bicleaner:
        message: f"Cleaning corpus using {bicleaner_type}"
        log: f"{log_dir}/bicleaner/{{dataset}}.log"
        conda: bicleaner_env
        group: "clean_corpus"
        threads: 1
        input: rules.kenlm.output, multiext(f"{clean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz"),
                pack_dir=rules.bicleaner_pack.output
        output: multiext(f"{biclean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
        params:
            prefix_input=f"{clean}/corpus/{{dataset}}",prefix_output=f"{biclean}/corpus/{{dataset}}",
            threshold=lambda wildcards: bicl_dataset_thresholds.get(wildcards.dataset) or bicl_default_threshold
        shell: '''bash pipeline/bicleaner/bicleaner.sh \
                    "{params.prefix_input}" "{params.prefix_output}" {params.threshold} {bicleaner_type} {threads} \
                    "{input.pack_dir}" >> {log} 2>&1'''

rule merge_corpus:
    message: "Merging clean parallel datasets"
    log: f"{log_dir}/merge_corpus.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    group: "clean_corpus"
    input:  expand(f"{clean_corpus_prefix}/{{dataset}}.{{lang}}.gz", dataset=train_datasets, lang=[src, trg])
    output: src=clean_corpus_src,trg=clean_corpus_trg
    params: prefix_output=clean_corpus_prefix, prefixes=expand(f"{clean_corpus_prefix}/{{dataset}}", dataset=train_datasets)
    shell: '''bash pipeline/clean/merge-corpus.sh "{params.prefix_output}" {params.prefixes} >> {log} 2>&1'''

rule merge_devset:
    message: "Merging devsets"
    log: f"{log_dir}/merge_devset.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    group: "clean_corpus"
    input:  expand(f"{original}/devset/{{dataset}}.{{lang}}.gz", dataset=valid_datasets, lang=[src, trg])
    output: multiext(f"{original}/devset", f".{src}.gz", f".{trg}.gz")
    params: prefix_output=f"{original}/devset", prefixes=expand(f"{original}/devset/{{dataset}}", dataset=valid_datasets)
    shell: '''bash pipeline/clean/merge-corpus.sh "{params.prefix_output}" {params.prefixes} >> {log} 2>&1'''

rule merge_mono:
    message: "Merging clean monolingual datasets"
    log: f"{log_dir}/merge_mono_{{lang}}.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    group: "clean_mono{lang}"
    input:
        lambda wildcards: expand(f"{clean}/mono/{{dataset}}.{{lang}}.gz",
            dataset=mono_datasets[wildcards.lang], lang=wildcards.lang)
    output: f"{clean}/mono.{{lang}}.gz"
    params: max_sent=lambda wildcards: mono_max_sent[wildcards.lang]
    shell: '''bash pipeline/clean/merge-mono.sh "{output}" {params.max_sent} {input} >> {log} 2>&1'''


# augmentation and teacher training

rule train_vocab:
    message: "Training spm vocab"
    log: f"{log_dir}/train_vocab.log"
    conda: "envs/base.yml"
    threads: 2
    input:
        bin=rules.marian.output.vocab,
        corpus_src=clean_corpus_src,corpus_trg=clean_corpus_trg
    output: f"{models_dir}/vocab/vocab.spm"
    params: prefix_train=clean_corpus_prefix,prefix_test=f"{original}/devset"
    shell: 'bash pipeline/train/spm-vocab.sh "{input.corpus_src}" "{input.corpus_trg}" "{output}" >> {log} 2>&1'


if train_backward:
    rule backward:
        message: "Training backward model"
        log: f"{log_dir}/train_backward.log"
        conda: "envs/base.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        group: 'backward'
        input:
            rules.merge_devset.output, train_src=clean_corpus_src,train_trg=clean_corpus_trg,
            bin=rules.marian.output.trainer, vocab=rules.train_vocab.output,
        output:  model=f'{backward}/{best_model}'
        params: prefix_train=f"{biclean}/corpus",prefix_test=f"{original}/devset",
                args=training_args.get("backward") or ""
        shell: '''bash pipeline/train/train.sh \
                    backward train {trg} {src} "{params.prefix_train}" "{params.prefix_test}" "{backward}" \
                    "{input.vocab}" {params.args} >> {log} 2>&1'''

    rule eval_backward:
        message: "Evaluating backward model"
        log: f"{log_dir}/eval_backward.log"
        conda: "envs/base.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        group: 'backward'
        priority: 50
        input:
            full_eval_datasets,
            model=f'{backward}/{best_model}'
        output:
            report(directory(eval_backward),patterns=["{name}.metrics"],
                category='evaluation', subcategory='finetuned', caption='reports/evaluation.rst')
        shell: 'bash pipeline/train/eval.sh "{eval_backward}" "{eval_data}" {trg} {src} {input.model} >> {log} 2>&1'



if augment_corpus:
    checkpoint split_mono_trg:
        message: "Splitting monolingual trg dataset"
        log: f"{log_dir}/split_mono_trg.log"
        conda: "envs/base.yml"
        threads: 1
        input: f"{clean}/mono.{trg}.gz"
        output: directory(f'{translated}/mono_trg')
        shell: 'bash pipeline/translate/split-mono.sh {input} {output} {split_length} >> {log} 2>&1'

    rule translate_mono_trg:
        message: "Translating monolingual trg dataset with backward model"
        log: f"{log_dir}/translate_mono_trg/{{part}}.log"
        conda: "envs/base.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        input:
            rules.marian.output.trainer,file=f'{translated}/mono_trg/file.{{part}}',
            vocab=rules.train_vocab.output,model=f'{backward}/{best_model}'
        output: f'{translated}/mono_trg/file.{{part}}.out'
        shell: 'bash pipeline/translate/translate.sh "{input.file}" "{input.vocab}" {input.model} >> {log} 2>&1'

    rule collect_mono_trg:
        message: "Collecting translated mono trg dataset"
        log: f"{log_dir}/collect_mono_trg.log"
        conda: "envs/base.yml"
        threads: 4
        group: 'mono_trg'
        input:
            lambda wildcards: expand(f"{translated}/mono_trg/file.{{part}}.out",
                part=find_parts(wildcards, checkpoints.split_mono_trg))
        output: f'{translated}/mono.{src}.gz'
        params: src_mono=f"{clean}/mono.{trg}.gz",dir=directory(f'{translated}/mono_trg')
        shell: 'bash pipeline/translate/collect.sh "{params.dir}" "{output}" "{params.src_mono}" >> {log} 2>&1'

    rule merge_augmented:
        message: "Merging augmented dataset"
        log: f"{log_dir}/merge_augmented.log"
        conda: "envs/base.yml"
        threads: 4
        group: 'mono_trg'
        input:
            src1=clean_corpus_src,src2=rules.collect_mono_trg.output,
            trg1=clean_corpus_trg,trg2=rules.split_mono_trg.input
        output: res_src=f'{augmented}/corpus.{src}.gz',res_trg=f'{augmented}/corpus.{trg}.gz'
        shell: '''bash pipeline/translate/merge-corpus.sh \
                    "{input.src1}" "{input.src2}" "{input.trg1}" "{input.trg2}" "{output.res_src}" "{output.res_trg}" \
                      >> {log} 2>&1'''



rule teacher_all:
    message: "Training teacher on all data"
    log: f"{log_dir}/train_teacher_all{{ens}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'teacher{ens}'
    input:
        rules.merge_devset.output, train_src=f'{teacher_corpus}.{src}.gz',train_trg=f'{teacher_corpus}.{trg}.gz',
        bin=rules.marian.output.trainer,vocab=rules.train_vocab.output
    output: model=f'{teacher_dir}{{ens}}/{teacher_all_output}'
    params: prefix_train=teacher_corpus, prefix_test=f"{original}/devset", dir=directory(f'{teacher_dir}{{ens}}'),
                args=training_args.get("teacher-all") or ""
    shell: '''bash pipeline/train/train.sh \
                teacher train {src} {trg} "{params.prefix_train}" "{params.prefix_test}" "{params.dir}" \
                "{input.vocab}" {params.args} >> {log} 2>&1'''

if continue_teacher:
    rule teacher_parallel:
        message: "Continue training teacher on parallel corpus"
        log: f"{log_dir}/train_teacher_parallel{{ens}}.log"
        conda: "envs/base.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        group: 'teacher{ens}'
        input:
            rules.merge_devset.output, model = f'{teacher_dir}{{ens}}/model.npz',
            train_src=clean_corpus_src,train_trg=clean_corpus_trg,
            bin=rules.marian.output.trainer,vocab=rules.train_vocab.output
        output: model=f'{teacher_dir}{{ens}}/{best_model}'
        params: prefix_train=clean_corpus_prefix,prefix_test=f"{original}/devset",dir=directory(f'{teacher_dir}{{ens}}'),
                args=training_args.get("teacher-parallel") or ""
        shell: '''bash pipeline/train/train.sh \
                    teacher continue {src} {trg} "{params.prefix_train}" "{params.prefix_test}" "{params.dir}" \
                    "{input.vocab}" {params.args} >> {log} 2>&1'''

rule eval_teacher:
    message: "Evaluating teacher model"
    log: f"{log_dir}/eval_teacher{{ens}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'teacher{ens}'
    priority: 50
    input:
        full_eval_datasets,
        model=f'{teacher_dir}{{ens}}/{best_model}'
    output:
        report(directory(f'{eval_res}/teacher{{ens}}'), patterns=["{name}.metrics"],
            category='evaluation', subcategory='teacher{ens}', caption='reports/evaluation.rst')
    params: dir=f'{eval_res}/teacher{{ens}}'
    shell: 'bash pipeline/train/eval.sh "{params.dir}" "{eval_data}" {src} {trg} {input.model} >> {log} 2>&1'


if len(ensemble) > 1:
    rule eval_teacher_ensemble:
        message: "Evaluating an ensemble of teacher models"
        log: f"{log_dir}/eval_teacher_ensemble.log"
        conda: "envs/base.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        priority: 50
        input:
            full_eval_datasets, models=[f'{teacher_dir}{ens}/{best_model}' for ens in ensemble]
        output:
            report(directory(eval_teacher_ens),patterns=["{name}.metrics"],
                category='evaluation',subcategory='teacher_ensemble',caption='reports/evaluation.rst')
        shell: 'bash pipeline/train/eval.sh "{eval_teacher_ens}" "{eval_data}" {src} {trg} {input.models} >> {log} 2>&1'


### translation with teacher

# corpus

checkpoint split_corpus:
    message: "Splitting the corpus to translate"
    log: f"{log_dir}/split_corpus.log"
    conda: "envs/base.yml"
    threads: 1
    input: corpus_src=clean_corpus_src,corpus_trg=clean_corpus_trg
    output: directory(f"{translated}/corpus")
    shell: '''bash pipeline/translate/split-corpus.sh \
                {input.corpus_src} {input.corpus_trg} {output} {split_length} >> {log} 2>&1'''

rule translate_corpus:
    message: "Translating corpus with teacher"
    log: f"{log_dir}/translate_corpus/{{part}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        rules.marian.output.trainer,
        file=f'{translated}/corpus/file.{{part}}',
        vocab=rules.train_vocab.output,
        teacher_models=expand(f"{teacher_dir}{{ens}}/{best_model}",ens=ensemble)
    output: f'{translated}/corpus/file.{{part}}.nbest'
    shell: '''bash pipeline/translate/translate-nbest.sh \
                "{input.file}" "{input.vocab}" {input.teacher_models} >> {log} 2>&1'''

rule extract_best:
    message: "Extracting best translations for the corpus"
    log: f"{log_dir}/extract_best/{{part}}.log"
    conda: "envs/base.yml"
    threads: 1
    group: 'translate_corpus'
    input: nbest=f"{translated}/corpus/file.{{part}}.nbest", ref=f"{translated}/corpus/file.{{part}}.ref"
    output: f"{translated}/corpus/file.{{part}}.nbest.out"
    shell: 'python pipeline/translate/bestbleu.py -i {input.nbest} -r {input.ref} -m bleu -o {output} >> {log} 2>&1'

rule collect_corpus:
    message: "Collecting translated corpus"
    log: f"{log_dir}/collect_corpus.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'translate_corpus'
    input:
        lambda wildcards: expand(f"{translated}/corpus/file.{{part}}.nbest.out",
            part=find_parts(wildcards, checkpoints.split_corpus))
    output: f'{translated}/corpus.{trg}.gz'
    params: src_corpus=clean_corpus_src
    shell: 'bash pipeline/translate/collect.sh {translated}/corpus {output} {params.src_corpus} >> {log} 2>&1'

# mono

checkpoint split_mono_src:
    message: "Splitting monolingual src dataset"
    log: f"{log_dir}/split_mono_src.log"
    conda: "envs/base.yml"
    threads: 1
    input: f"{clean}/mono.{src}.gz"
    output: directory(f'{translated}/mono_src')
    shell: 'bash pipeline/translate/split-mono.sh {input} {output} {split_length} >> {log} 2>&1'

rule translate_mono_src:
    message: "Translating monolingual src dataset with teacher"
    log: f"{log_dir}/translate_mono_src/{{part}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        bin=rules.marian.output.trainer,
        file=f'{translated}/mono_src/file.{{part}}',vocab=rules.train_vocab.output,
        teacher_models=expand(f"{teacher_dir}{{ens}}/{best_model}",ens=ensemble)
    output: f'{translated}/mono_src/file.{{part}}.out'
    shell: 'bash pipeline/translate/translate.sh "{input.file}" "{input.vocab}" {input.teacher_models} >> {log} 2>&1'

rule collect_mono_src:
    message: "Collecting translated mono src dataset"
    log: f"{log_dir}/collect_mono_src.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'mono_src'
    input:
       lambda wildcards: expand(f"{translated}/mono_src/file.{{part}}.out",
           part=find_parts(wildcards, checkpoints.split_mono_src))
    output: f'{translated}/mono.{trg}.gz'
    params: src_mono=f"{clean}/mono.{src}.gz",dir=f'{translated}/mono_src'
    shell: 'bash pipeline/translate/collect.sh "{params.dir}" "{output}" "{params.src_mono}" >> {log} 2>&1'

# merge

rule merge_translated:
    message: "Merging translated datasets"
    log: f"{log_dir}/merge_translated.log"
    conda: "envs/base.yml"
    threads: 4
    group: 'mono_src'
    input:
        src1=clean_corpus_src,src2=f"{clean}/mono.{src}.gz",
        trg1=rules.collect_corpus.output,trg2=rules.collect_mono_src.output
    output: res_src=f'{merged}/corpus.{src}.gz',res_trg=f'{merged}/corpus.{trg}.gz'
    shell: '''bash pipeline/translate/merge-corpus.sh \
                "{input.src1}" "{input.src2}" "{input.trg1}" "{input.trg2}" "{output.res_src}" "{output.res_trg}" \
                  >> {log} 2>&1'''

# train student

rule score:
    message: "Scoring"
    log: f"{log_dir}/score.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        model=rules.backward.output.model,vocab=rules.train_vocab.output,
        src_corpus=rules.merge_translated.output.res_src,trg_corpus=rules.merge_translated.output.res_trg
    output: f"{filtered}/scores.txt"
    params: input_prefix=f'{merged}/corpus'
    shell: '''bash pipeline/cefilter/score.sh \
                "{input.model}" "{input.vocab}" "{params.input_prefix}" "{output}" >> {log} 2>&1'''

rule ce_filter:
    message: "Cross entropy filtering"
    log: f"{log_dir}/ce_filter.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    resources: mem_mb=workflow.cores*5000
    input:
        src_corpus=rules.merge_translated.output.res_src,trg_corpus=rules.merge_translated.output.res_trg,
        scores=rules.score.output
    output: src_corpus=f"{filtered}/corpus.{src}.gz",trg_corpus=f"{filtered}/corpus.{trg}.gz"
    params: input_prefix=f'{merged}/corpus',output_prefix=f'{filtered}/corpus'
    shell: '''bash pipeline/cefilter/ce-filter.sh \
                "{params.input_prefix}" "{params.output_prefix}" "{input.scores}" >> {log} 2>&1'''

rule alignments:
    message: 'Training word alignment and lexical shortlists'
    log: f"{log_dir}/alignments.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    input: src_corpus=rules.ce_filter.output.src_corpus,trg_corpus=rules.ce_filter.output.trg_corpus,
        vocab=rules.train_vocab.output,
        fast_align=rules.fast_align.output.fast_align, atools=rules.fast_align.output.atools,
        extract_lex=rules.extract_lex.output
    output: alignment=f'{align_dir}/corpus.aln.gz',shortlist=f'{align_dir}/lex.s2t.pruned.gz'
    params: input_prefix=f'{filtered}/corpus'
    shell: '''bash pipeline/alignment/generate-alignment-and-shortlist.sh \
                "{params.input_prefix}" "{input.vocab}" "{align_dir}" {threads} >> {log} 2>&1'''

rule student:
    message: "Training student"
    log: f"{log_dir}/train_student.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'student'
    input:
        rules.merge_devset.output, train_src=rules.ce_filter.output.src_corpus, train_trg=rules.ce_filter.output.trg_corpus,
        alignments=rules.alignments.output.alignment,
        bin=rules.marian.output.trainer, vocab=rules.train_vocab.output
    output: model=f'{student_dir}/{best_model}'
    params: prefix_train=rules.ce_filter.params.output_prefix,prefix_test=f"{original}/devset",
            args=training_args.get("student") or ""
    shell: '''bash pipeline/train/train-student.sh \
                "{input.alignments}" student train {src} {trg} "{params.prefix_train}" "{params.prefix_test}" \
                "{student_dir}" "{input.vocab}" {params.args} >> {log} 2>&1'''

rule eval_student:
    message: "Evaluating student model"
    log: f"{log_dir}/eval_student.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'student'
    priority: 50
    input: full_eval_datasets, model=rules.student.output.model
    output:
        report(directory(eval_student),patterns=["{name}.metrics"],category='evaluation',
            subcategory='student', caption='reports/evaluation.rst')
    shell: 'bash pipeline/train/eval.sh "{eval_student}" "{eval_data}" {src} {trg} {input.model} >> {log} 2>&1'

# quantize

rule finetune_student:
    message: "Fine-tuning student"
    log: f"{log_dir}/finetune_student.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'finetune'
    input:
        rules.merge_devset.output, train_src=rules.ce_filter.output.src_corpus, train_trg=rules.ce_filter.output.trg_corpus,
        alignments=rules.alignments.output.alignment, student_model=rules.student.output.model,
        bin=rules.marian.output.trainer, vocab=rules.train_vocab.output
    output: model=f'{student_finetuned_dir}/{best_model}'
    params: prefix_train=rules.ce_filter.params.output_prefix,prefix_test=f"{original}/devset",
            args=training_args.get("student-finetune") or ""
    shell: '''bash pipeline/train/train-student.sh \
                "{input.alignments}" student finetune {src} {trg} "{params.prefix_train}" "{params.prefix_test}" \
                "{student_finetuned_dir}" "{input.vocab}" {params.args} >> {log} 2>&1'''

rule eval_finetuned_student:
    message: "Evaluating fine-tuned student model"
    log: f"{log_dir}/eval_finetuned_student.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    group: 'finetune'
    priority: 50
    input: full_eval_datasets, model=rules.finetune_student.output.model
    output:
        report(directory(eval_student_finetuned),patterns=["{name}.metrics"],
            category='evaluation', subcategory='finetuned', caption='reports/evaluation.rst')
    shell: 'bash pipeline/train/eval.sh "{eval_student_finetuned}" "{eval_data}" {src} {trg} {input.model} \
                >> {log} 2>&1'

rule quantize:
    message: "Quantization"
    log: f"{log_dir}/quntize.log"
    conda: "envs/base.yml"
    threads: 1
    input:
        shortlist=rules.alignments.output.shortlist, model=rules.finetune_student.output.model,
        bin=rules.marian.output.decoder, vocab=rules.train_vocab.output, devset=f"{original}/devset.{src}.gz"
    output: model=f'{speed}/model.intgemm.alphas.bin'
    shell: 'bash pipeline/quantize/quantize.sh \
                "{input.model}" "{input.vocab}" "{input.shortlist}" "{input.devset}" "{speed}" >> {log} 2>&1'''

rule eval_quantized:
    message: "Evaluating qunatized student model"
    log: f"{log_dir}/eval_quantized.log"
    conda: "envs/base.yml"
    group: 'export'
    threads: 1
    priority: 50
    input:
        full_eval_datasets,
        model=rules.quantize.output.model,
        shortlist=rules.alignments.output.shortlist,vocab=rules.train_vocab.output
    output:
        report(directory(eval_speed),patterns=["{name}.metrics"], category='evaluation',
            subcategory='quantized', caption='reports/evaluation.rst')
    shell: '''bash pipeline/quantize/eval.sh "{speed}" "{input.shortlist}" "{eval_data}" "{input.vocab}" "{eval_speed}" \
            >> {log} 2>&1'''

rule export:
    message: "Exporting models"
    log: f"{log_dir}/export.log"
    conda: "envs/base.yml"
    group: 'export'
    threads: 1
    input:
        model=rules.quantize.output.model,shortlist=rules.alignments.output.shortlist,
        vocab=rules.train_vocab.output,marian=rules.marian.output.converter
    output:
        model=f'{exported}/model.{src}{trg}.intgemm.alphas.bin.gz',
        shortlist=f'{exported}/lex.50.50.{src}{trg}.s2t.bin.gz',
        vocab=f'{exported}/vocab.{src}{trg}.spm.gz'
    shell: 'bash pipeline/quantize/export.sh "{speed}" "{input.shortlist}" "{input.vocab}" "{exported}" >> {log} 2>&1'