require 'xcodeproj'
project_path = '/Users/pc/Documents/JTACXCode/JTAC.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.root_object.package_references.clear
project.targets.first.package_product_dependencies.clear

pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = 'https://github.com/ml-explore/mlx-swift.git'
pkg_ref.requirement = {'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.22.0'}
project.root_object.package_references << pkg_ref

mlx_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
mlx_product.product_name = 'MLX'
mlx_product.package = pkg_ref
project.targets.first.package_product_dependencies << mlx_product

pkg_ref2 = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref2.repositoryURL = 'https://github.com/ml-explore/mlx-swift-examples.git'
pkg_ref2.requirement = {'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.2.0'}
project.root_object.package_references << pkg_ref2

llm_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
llm_product.product_name = 'LLM'
llm_product.package = pkg_ref2
project.targets.first.package_product_dependencies << llm_product

project.save
puts "Packages re-added correctly!"
