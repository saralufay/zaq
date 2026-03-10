defmodule Zaq.Repo.Migrations.CreateRetrievalChannels do
  use Ecto.Migration

  def change do
    create table(:retrieval_channels) do
      add :channel_config_id, references(:channel_configs, on_delete: :delete_all), null: false
      add :channel_id, :string, null: false
      add :channel_name, :string, null: false
      add :team_id, :string, null: false
      add :team_name, :string, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:retrieval_channels, [:channel_config_id])
    create unique_index(:retrieval_channels, [:channel_config_id, :channel_id])
  end
end
