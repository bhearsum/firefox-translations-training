from taskgraph.transforms.base import TransformSequence
from taskgraph.util.hash import hash_path

transforms = TransformSequence()

@transforms.add
def add_cache(config, jobs):
    for job in jobs:
        cache = job["attributes"]["cache"]
        cache_type = cache["type"]
        cache_resources = cache["resources"]
        cache_parameters = cache.get("parameters", {})
        digest_data = []

        if cache_resources:
            for r in cache_resources:
                digest_data.append(hash_path(r))

        if cache_parameters:
            for p in cache_parameters:
                # TODO: this should somehow find the default value for each paramater...
                digest_data.append(config.params.get(p, ""))

        job["cache"] = {
            "type": cache_type,
            "name": job["label"],
            "digest-data": digest_data,
        }

        yield job
