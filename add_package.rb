require 'xcodeproj'
project_path = '/Users/pc/Documents/JTACXCode/JTAC.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Check if phase exists
frameworks_phase = target.frameworks_build_phase

# MLX setup
pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = 'https://github.com/ml-explore/mlx-swift.git'
pkg_ref.requirement = {'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.22.0'}
project.root_object.package_references << pkg_ref

mlx_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mlx_product.product_name = 'MLX'
mlx_product.package = pkg_ref
target.package_product_dependencies << mlx_product

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = mlx_product
frameworks_phase.files << build_file

# MLXLM setup
pkg_ref2 = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref2.repositoryURL = 'https://github.com/ml-explore/mlx-swift-examples.git'
pkg_ref2.requirement = {'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.2.0'} # mlx-swift-examples is newer
project.root_object.package_references << pkg_ref2

mlx_lm_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mlx_lm_product.product_name = 'MLXLM'
mlx_lm_product.package = pkg_ref2
target.package_product_dependencies << mlx_lm_product

build_file2 = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file2.product_ref = mlx_lm_product
frameworks_phase.files << build_file2

project.save
puts "Added Packages!"
