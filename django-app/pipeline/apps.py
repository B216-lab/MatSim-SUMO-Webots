import sys

from django.apps import AppConfig


class PipelineConfig(AppConfig):
    name = "pipeline"
    verbose_name = "Pipeline"

    def ready(self):
        if "test" in sys.argv:
            return
        from pipeline.queues import get_pipeline

        get_pipeline()
