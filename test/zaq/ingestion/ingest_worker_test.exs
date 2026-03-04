defmodule Zaq.Ingestion.IngestWorkerTest do
  use Zaq.DataCase, async: false

  import Mox

  alias Zaq.Ingestion.{IngestJob, IngestWorker}
  alias Zaq.Repo

  setup do
    Mox.set_mox_global()
    :ok
  end

  setup :verify_on_exit!

  defp create_job(attrs \\ %{}) do
    %IngestJob{}
    |> IngestJob.changeset(
      Map.merge(%{file_path: "docs/test.md", status: "pending", mode: "async"}, attrs)
    )
    |> Repo.insert!()
  end

  describe "perform/1" do
    test "sets status to completed on success" do
      job = create_job()

      expect(Zaq.DocumentProcessorMock, :process_single_file, fn _path ->
        {:ok, %{id: nil, chunks_count: 5, document_id: nil}}
      end)

      assert :ok =
               IngestWorker.perform(%Oban.Job{
                 args: %{"job_id" => job.id},
                 attempt: 1,
                 max_attempts: 3
               })

      updated = Repo.get!(IngestJob, job.id)
      assert updated.status == "completed"
      assert updated.chunks_count == 0
      assert updated.started_at != nil
      assert updated.completed_at != nil
    end

    test "sets status to failed on error" do
      job = create_job()

      expect(Zaq.DocumentProcessorMock, :process_single_file, fn _path ->
        {:error, :parse_error}
      end)

      assert {:cancel, :parse_error} =
               IngestWorker.perform(%Oban.Job{
                 args: %{"job_id" => job.id},
                 attempt: 3,
                 max_attempts: 3
               })

      updated = Repo.get!(IngestJob, job.id)
      assert updated.status == "failed"
      assert updated.error =~ "parse_error"
      assert updated.completed_at != nil
    end
  end
end
