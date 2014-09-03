require 'octokit'
require 'fileutils'
require 'csv'
require 'netrc'

$organization = ARGV[0]

$dir = Time.now.strftime('%Y%m%d_%H%M%S')

# csv出力先
FileUtils.mkdir_p($dir) unless FileTest.exist?($dir)

# init Octokit
Octokit.configure do |c|
  c.netrc = true
  c.auto_paginate = true
end
$client = Octokit.client

# =============================================================================
# == functions
# =============================================================================

# orgのmembersを取るときにauto_paginateが効かないようなので
# 100件ずつ自力paginateして全件取得するラッパー
def get_octo_data(path)
  data = $client.get(path, per_page: 100)
  next_page = $client.last_response.rels[:last]
  return data unless next_page

  page_count = next_page.href.match(/page=(\d+)$/)[1].to_i
  (page_count - 1).times do
    data.concat $client.last_response.rels[:next].get.data
  end

  data
end

def create_userlist(path, users)
  CSV.open(path, "wb") do |csv|
    csv << ["name", "url", "admin", "2fa_disabled"]
    users.each do |user|
      csv << [user.login, user.html_url, user.site_adimin, user.two_fa_disabled]
    end
  end
end

# =============================================================================
# == main
# =============================================================================

# リポジトリリスト
repos = get_octo_data("/orgs/#{$organization}/repos")
CSV.open("#{$dir}/repos.csv", "wb") do |csv|
  csv << ["name", "full_name", "url", "owner", "private"]
  repos.each do |repo|
    csv << [repo.name, repo.full_name, repo.full_name, repo.owner.login, repo.private]
  end
end

# 全メンバーリスト
org_members = get_octo_data("/orgs/#{$organization}/members")
# 2段階認証してない人をマーク(filterで取るしかない)
two_fa_disabled_user_ids = get_octo_data("/orgs/#{$organization}/members?filter=2fa_disabled").map{|t| t.id}
org_members.each do |u|
  u.two_fa_disabled = two_fa_disabled_user_ids.include?(u.id)
end
create_userlist("#{$dir}/all_members.csv", org_members)

# チーム別リスト
teams = get_octo_data("/orgs/#{$organization}/teams")
teams.each do |team|
  # メンバー取得
  team_members = get_octo_data("teams/#{team.id}/members")
  create_userlist("#{$dir}/#{team.name.downcase.gsub(" ", "_")}_#{team.id}_members.csv", team_members)
end
