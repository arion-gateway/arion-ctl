defmodule Arion.ControlPlane.Pb.Envoy.Service.Discovery.V3.AggregatedDiscoveryService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "envoy.service.discovery.v3.AggregatedDiscoveryService",
    protoc_gen_elixir_version: "0.17.0"

  rpc :DeltaAggregatedResources,
      stream(Arion.ControlPlane.Pb.Data.DeltaDiscoveryRequest),
      stream(Arion.ControlPlane.Pb.Data.DeltaDiscoveryResponse)
end

defmodule Arion.ControlPlane.Pb.Envoy.Service.Discovery.V3.AggregatedDiscoveryService.Stub do
  @moduledoc false

  use GRPC.Stub,
    service: Arion.ControlPlane.Pb.Envoy.Service.Discovery.V3.AggregatedDiscoveryService.Service
end
