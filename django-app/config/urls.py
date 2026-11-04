from django.urls import path

from pipeline.views import endpoint

urlpatterns = [
    path("", endpoint),
]
